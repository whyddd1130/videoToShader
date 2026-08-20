#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float u_sampleX;
uniform float u_sigmaX;
uniform float u_stepX;
uniform float u_sigmaColor;

#define MAX_SAMPLE 1024

const float Eps = 1e-5;

vec4 getBilateralWeight(float x, vec4 colorDiff, float spaceFactor, float colorFactor)
{
    return exp(x * x * spaceFactor + colorDiff * colorDiff * colorFactor);
}

void main()
{
    if (u_sampleX < Eps) {
        gl_FragColor = texture2D(inputImageTexture, textureCoord);
        return;
    }

    float spaceFactor = -0.5 / (u_sigmaX * u_sigmaX);
    float colorFactor = -0.5 / (u_sigmaColor * u_sigmaColor);

    vec4 oriColor = texture2D(inputImageTexture, textureCoord);
    vec4 sumWeight = getBilateralWeight(0., vec4(0.), spaceFactor, colorFactor);
    vec4 sumColor = sumWeight * oriColor;

    vec2 uv = textureCoord;
    for (int i = 1; i <= MAX_SAMPLE; i++) {
        float k = float(i);
        if (k > u_sampleX) {
            break;
        }
        float x = k * u_stepX;
        uv.x = textureCoord.x - x;
        if (uv.x > 0.) {
            vec4 color = texture2D(inputImageTexture, uv);
            vec4 weight = getBilateralWeight(x, oriColor - color, spaceFactor, colorFactor);
            sumColor += weight * color;
            sumWeight += weight;
        }
        uv.x = textureCoord.x + x;
        if (uv.x < 1.) {
            vec4 color = texture2D(inputImageTexture, uv);
            vec4 weight = getBilateralWeight(x, oriColor - color, spaceFactor, colorFactor);
            sumColor += weight * color;
            sumWeight += weight;
        }
    }
    sumColor /= sumWeight;
    gl_FragColor = sumColor;
}
