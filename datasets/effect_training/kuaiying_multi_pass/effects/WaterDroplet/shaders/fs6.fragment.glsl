#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_Center;
uniform vec2 u_ScreenParams;
uniform float u_Amount;
uniform float u_Quality;
#define PI 3.1415926
vec2 rotate(vec2 uv, vec2 center, float angle)
{
    float theta = angle * PI / 180.0;
    float sint = sin(theta), cost = cos(theta);
    uv -= center;
    uv.x *= u_ScreenParams.x/u_ScreenParams.y;
    uv = mat2(cost, sint, -sint, cost) * uv;
    uv.x /= u_ScreenParams.x/u_ScreenParams.y;
    return uv + center;
}
void main()
{
    const int SAMPLES = 32;
    float quality = clamp(u_Quality * 0.01, 0.1, 1.0) * 2.6 * u_ScreenParams.x / 720.0;
    float amount = u_Amount * 7.9;
    vec2 uv = textureCoord;
    float x = length(uv - u_Center);
    float weight = 0.0;
    vec4 res = texture2D(inputImageTexture, uv) * weight;
    float sumWeight = weight;
    float s = abs(amount) * x * quality * 0.5 + 1.0;
    float angle = 0.225;
    float a = 0.0;

    const float maxSamples = 40.;     // Custom Value;
    angle = angle * (amount) / maxSamples;
    for (float i = 0.0; i < maxSamples; i += 1.0)
    {
        weight = 1.0;
        vec2 tmpUV = rotate(uv, u_Center, -(amount) * 0.225 * 0.5 + mix(0., maxSamples, i/maxSamples) * angle);
        res += texture2D(inputImageTexture, tmpUV) * weight;
        sumWeight += weight;
    }

    gl_FragColor = vec4(res / sumWeight);
}
