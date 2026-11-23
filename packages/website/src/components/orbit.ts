const vertexSource = `
attribute vec2 position;
void main() {
  gl_Position = vec4(position, 0.0, 1.0);
}
`;

const fragmentSource = `
precision mediump float;
uniform vec2 resolution;
uniform float intensity;
uniform float phase;

void main() {
  vec2 p = (gl_FragCoord.xy / resolution - 0.5) * 2.0;
  p.x *= resolution.x / resolution.y;
  p = mat2(0.97, -0.24, 0.24, 0.97) * p;
  p.y *= 2.5;
  float angle = atan(p.y, p.x);
  float radius = length(p);
  float ripple = sin(angle * 3.0 - phase * 6.283);
  float distance = radius - (1.13 + 0.08 * ripple);
  float ring = exp(-50.0 * distance * distance);
  float halo = exp(-10.0 * distance * distance);
  vec3 rainbow = 0.64 + 0.35 * cos(
    angle + phase * 6.283 + radius * 2.0 + vec3(0.0, 2.094, 4.189)
  );
  float glint = 0.5 + 0.5 * cos(angle - phase * 6.283);
  gl_FragColor = vec4(rainbow, intensity * (ring * (0.35 + glint * 0.37) + halo * 0.17));
}
`;

export function createOrbit(canvas: HTMLCanvasElement) {
  const gl = canvas.getContext('webgl', { premultipliedAlpha: false, antialias: false });
  if (!gl) return;

  const program = gl.createProgram();
  if (!program) return;

  for (const [type, source] of [
    [gl.VERTEX_SHADER, vertexSource],
    [gl.FRAGMENT_SHADER, fragmentSource],
  ] as const) {
    const shader = gl.createShader(type);
    if (!shader) return;
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    gl.attachShader(program, shader);
    gl.deleteShader(shader);
  }

  gl.linkProgram(program);
  const buffer = gl.createBuffer();
  if (!buffer || !gl.getProgramParameter(program, gl.LINK_STATUS)) return;

  gl.useProgram(program);
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const position = gl.getAttribLocation(program, 'position');
  gl.enableVertexAttribArray(position);
  gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

  const resolution = gl.getUniformLocation(program, 'resolution');
  const intensity = gl.getUniformLocation(program, 'intensity');
  const phase = gl.getUniformLocation(program, 'phase');

  return {
    draw(light: number, rotation: number) {
      const dpr = Math.min(window.devicePixelRatio, 2);
      const width = Math.round(canvas.clientWidth * dpr);
      const height = Math.round(canvas.clientHeight * dpr);
      if (!width || !height) return;
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
      gl.viewport(0, 0, width, height);
      gl.uniform2f(resolution, width, height);
      gl.uniform1f(intensity, light);
      gl.uniform1f(phase, rotation);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    },
  };
}
