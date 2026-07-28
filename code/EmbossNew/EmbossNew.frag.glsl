precision highp float;

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;

void main() {
    float p = clamp(uProgress, 0.0, 1.0);
    float intensity = mix(0.35, 1.25, p);
    vec2 stepUv = vec2(0.02) * p;
    vec2 uv = textureCoord;

    vec3 a = texture2D(inputImageTexture, clamp(uv - stepUv, 0.0, 1.0)).rgb;
    vec3 b = texture2D(inputImageTexture, uv).rgb;
    vec3 c = texture2D(inputImageTexture, clamp(uv + stepUv, 0.0, 1.0)).rgb;
    vec3 embossed = clamp(0.5 + intensity * (2.0 * a - b - c), 0.0, 1.0);
    // The original effect starts from a uniform neutral-gray convolution
    // field, then progressively reveals the embossed structure.
    gl_FragColor = vec4(mix(vec3(0.5), embossed, p), 1.0);
}
