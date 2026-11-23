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
uniform float time;

void main() {
  vec2 p = (gl_FragCoord.xy / resolution - 0.5) * 2.0;
  float alpha = exp(-3.8 * dot(p, p));
  vec3 rainbow = 0.75 + 0.24 * cos(
    p.x * 4.0 + p.y * 2.0 + vec3(0.0, 2.094, 4.189)
  );
  float depth = clamp((-p.y - 0.34) / 0.66, 0.0, 1.0);
  float water = smoothstep(0.0, 0.18, depth) * (1.0 - smoothstep(0.67, 1.0, depth));
  float current = sin(depth * 19.0 - time * 0.75);
  float center = p.x - 0.035 * current;
  float spread = 0.045 + 0.43 * depth;
  float reflection = exp(-abs(center) / spread);
  float ripples = 0.5 + 0.5 * sin(depth * 84.0 - time * 2.2 + 2.0 * sin(p.x * 7.0 + depth * 8.0));
  float brokenLight = 0.55 + 0.45 * sin(p.x * 37.0 + depth * 41.0 + time);
  float shimmer = water * reflection * (0.14 + 0.86 * pow(ripples, 5.0)) * brokenLight;
  vec3 silver = mix(vec3(0.39, 0.58, 0.80), vec3(0.86, 0.93, 1.0), ripples);

  float daylight = intensity * alpha * 0.26;
  float moonlight = (1.0 - intensity) * shimmer;
  vec3 color = (daylight * rainbow + moonlight * silver) / max(daylight + moonlight, 0.001);
  gl_FragColor = vec4(color, daylight + moonlight);
}
`;

export function createAmbientLight(canvas: HTMLCanvasElement) {
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
  const time = gl.getUniformLocation(program, 'time');

  return {
    draw(light: number, seconds: number) {
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
      gl.uniform1f(time, seconds);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    },
  };
}
