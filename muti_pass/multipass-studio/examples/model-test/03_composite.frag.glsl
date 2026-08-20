precision highp float;
varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;

void main() {
    vec2 px = vec2(1.0 / 1024.0, 1.0 / 1024.0);
    vec3 c = texture2D(inputImageTexture, textureCoord).rgb;
    vec3 right = texture2D(inputImageTexture, textureCoord + vec2(px.x, 0.0)).rgb;
    vec3 up = texture2D(inputImageTexture, textureCoord + vec2(0.0, px.y)).rgb;
    float edge = length(c - right) + length(c - up);
    float p = smoothstep(0.0, 1.0, uProgress);
    vec3 tint = mix(vec3(1.0), vec3(1.10, 0.88, 1.20), p);
    vec3 result = (c - 0.5) * (1.0 + 0.20 * p) + 0.5;
    result = result * tint + edge * vec3(0.25, 0.65, 1.0) * p;
    gl_FragColor = vec4(result, 1.0);
}
