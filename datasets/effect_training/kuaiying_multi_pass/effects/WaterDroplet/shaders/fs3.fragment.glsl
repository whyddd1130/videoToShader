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

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
void main()
{
    float quality = clamp(u_Quality * 0.01, 0.1, 1.0) * 12.0;
    float amount = u_Amount * u_ScreenParams.x / 720.0;
    vec2 uv = textureCoord;
    vec2 dir = normalize(uv - u_Center);
    float x = length(uv - u_Center);
    dir = dir / u_ScreenParams.x * 8.0 * sign(amount) / quality;
    float sigma = (abs(amount) * 0.2 * quality + 1.0) * x;
    float weight = normpdf(0.0, sigma);
    vec4  res = texture2D(inputImageTexture, uv) * weight;
    float sumWeight = weight;

    float s = (quality * abs(amount) * 0.5 + 1.0) * x;

    const float maxSamples = 45.;     // Custom Value;

    for (float i = 1.0; i < maxSamples; i += 1.0)
    {
        weight = normpdf(float(i), sigma);
        vec4 tmp = (texture2D(inputImageTexture, uv - mix(1., s, (i-1.)/maxSamples) * dir)) * weight;
        res += tmp;
        sumWeight += weight;
    }
    gl_FragColor = vec4(res / sumWeight);
}
