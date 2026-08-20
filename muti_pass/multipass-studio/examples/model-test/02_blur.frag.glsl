precision highp float;
varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;

void main() {
    float amount = 0.008 * smoothstep(0.15, 0.85, uProgress);
    vec2 direction = normalize(vec2(1.0, 0.35)) * amount;
    vec4 color = texture2D(inputImageTexture, textureCoord) * 0.30;
    color += texture2D(inputImageTexture, textureCoord - direction * 2.0) * 0.10;
    color += texture2D(inputImageTexture, textureCoord - direction) * 0.20;
    color += texture2D(inputImageTexture, textureCoord + direction) * 0.20;
    color += texture2D(inputImageTexture, textureCoord + direction * 2.0) * 0.10;
    color += texture2D(inputImageTexture, textureCoord + direction * 3.0) * 0.10;
    gl_FragColor = color;
}
