#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;

float random(vec3 p3)
{
    p3 = fract(p3 * 100.0);
    p3 += dot(p3, p3.yzx + 11.0);
    return fract((p3.x + p3.y) * p3.z);
}

void main()
{
    const float TAU = 6.28318530718;
    vec2 uv = textureCoord;
    float p = clamp(uProgress, 0.0, 1.0);

    // Original parameters: speed 0 -> 2, samples 1 -> 50 over five seconds.
    float sourceTime = p * 5.0;
    float speed = 2.0 * p;
    float activeSamples = mix(1.0, 50.0, p);
    float radius = 0.05 + 0.05 * sin(sourceTime * speed * TAU + 14.3);
    vec4 color = vec4(0.0);

    // Static upper bound keeps the loop valid on the Shader Lab GLSL runtime.
    for (int i = 0; i < 50; ++i) {
        float fi = float(i);
        if (fi < activeSamples) {
            float rnd = random(vec3(uv, fi));
            float f = ((fi + rnd) / activeSamples * 2.0 - 1.0) * radius;
            color = max(texture2D(inputImageTexture, uv + vec2(f, 0.0)), color);
        }
    }
    gl_FragColor = color;
}
