#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;
varying vec2 textureCoord;

const float SAMPLES = 12.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(41.0, 289.0))) * 45758.5453);
}

void main() {
    vec2 uv0 = textureCoord;
    vec2 uv = textureCoord;
    float p = clamp(uProgress, 0.0, 1.0);
    vec2 glowCenter = vec2(0.5) + vec2(sin(uTime * 0.31), cos(uTime * 0.23)) * 0.08;
    float strength = mix(0.18, 1.25, p);
    float density = mix(0.12, 1.35, p);
    vec2 lightDir = normalize(vec2(1.5, 1.0));
    vec2 tuv = uv - glowCenter - lightDir * 0.01;
    vec2 dTuv = tuv * density / SAMPLES;
    float weight = 0.1;
    vec4 col = texture2D(inputImageTexture, uv) * strength;
    uv += dTuv * (hash(uv + fract(uTime)) * 2.0 - 1.0);

    for (float i = 0.0; i < SAMPLES; i++) {
        uv -= dTuv;
        col += texture2D(inputImageTexture, clamp(uv, 0.0, 1.0)) * weight;
        weight *= 0.97;
    }
    col *= max(0.0, 1.0 - dot(tuv, tuv) * 0.75);
    vec4 resultColor = sqrt(clamp(col, 0.0, 1.0));
    resultColor.a = texture2D(inputImageTexture, uv0).a;
    gl_FragColor = resultColor;
}
