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

vec3 oklchToLinearP3(float lightness, float chroma, float hue) {
  float a = chroma * cos(hue);
  float b = chroma * sin(hue);
  vec3 lms = lightness + a * vec3(0.3963378, -0.1055613, -0.0894842)
    + b * vec3(0.2158038, -0.0638542, -1.2914855);
  lms = lms * lms * lms;

  // Combine the LMS-to-XYZ and XYZ-to-Display-P3 transforms.
  return mat3(
    3.127769, -1.091009, -0.026011,
    -2.257136, 2.413332, -0.508041,
    0.129367, -0.322323, 1.534052
  ) * lms;
}

void main() {
  vec2 p = (gl_FragCoord.xy / resolution - 0.5) * 2.0;
  float alpha = exp(-3.8 * dot(p, p));
  float hue = 3.7 + p.x * 2.2 + p.y * 1.25;
  vec3 rainbow = oklchToLinearP3(0.82, 0.105, hue);
  float depth = clamp((-p.y - 0.34) / 0.66, 0.0, 1.0);
  float water = smoothstep(0.0, 0.18, depth) * (1.0 - smoothstep(0.67, 1.0, depth));
  float current = sin(depth * 19.0 - time * 0.75);
  float center = p.x - 0.035 * current;
  float spread = 0.045 + 0.43 * depth;
  float reflection = exp(-abs(center) / spread);
  float ripples = 0.5 + 0.5 * sin(depth * 84.0 - time * 2.2 + 2.0 * sin(p.x * 7.0 + depth * 8.0));
  float brokenLight = 0.55 + 0.45 * sin(p.x * 37.0 + depth * 41.0 + time);
  float shimmer = water * reflection * (0.14 + 0.86 * pow(ripples, 5.0)) * brokenLight;
  vec3 silver = oklchToLinearP3(
    mix(0.66, 0.95, ripples),
    mix(0.11, 0.027, ripples),
    radians(mix(252.0, 246.0, ripples))
  );

  float daylight = intensity * alpha * 0.26;
  float moonlight = (1.0 - intensity) * shimmer;
  vec3 color = (daylight * rainbow + moonlight * silver) / max(daylight + moonlight, 0.001);
  vec3 linearColor = clamp(color, 0.0, 1.0);
  vec3 encodedColor = mix(
    linearColor * 12.92,
    1.055 * pow(linearColor, vec3(1.0 / 2.4)) - 0.055,
    step(vec3(0.0031308), linearColor)
  );
  gl_FragColor = vec4(encodedColor, daylight + moonlight);
}
`;

export function createAmbientLight(canvas: HTMLCanvasElement) {
  const gl = canvas.getContext('webgl', { premultipliedAlpha: false, antialias: false });
  if (!gl || !('drawingBufferColorSpace' in gl)) return;
  gl.drawingBufferColorSpace = 'display-p3';
  if (gl.drawingBufferColorSpace !== 'display-p3') return;

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
