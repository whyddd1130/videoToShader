precision highp float;
varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;

void main() {
    vec2 centered = textureCoord - 0.5;
    float p = smoothstep(0.0, 1.0, uProgress);
    float radius = length(centered);
    float lens = 1.0 - 0.20 * p * exp(-radius * 5.0);
    vec2 uv = centered * lens + 0.5;
    uv.x += sin(uv.y * 10.0 + uTime * 1.4) * 0.025 * p;
    gl_FragColor = texture2D(inputImageTexture, uv);
}
