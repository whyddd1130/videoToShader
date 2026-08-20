#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float u_sampleY;
uniform float u_sigmaY;
uniform float u_stepY;
uniform float u_sigmaColor;

#define MAX_SAMPLE 1024
const float Eps = 1e-5;

vec4 getBilateralWeight(float x, vec4 colorDist, float spaceFactor, float colorFactor)
{
    return exp(x * x * spaceFactor + colorDist * colorDist * colorFactor);
}

void main()
{
    if (u_sampleY < Eps) {
        gl_FragColor = texture2D(inputImageTexture, textureCoord);
        return;
    }

    float spaceFactor = -0.5 / (u_sigmaY * u_sigmaY);
    float colorFactor = -0.5 / (u_sigmaColor * u_sigmaColor);
    vec4 oriColor = texture2D(inputImageTexture, textureCoord);
    vec4 sumWeight = getBilateralWeight(0., vec4(0.), spaceFactor, colorFactor);
    vec4 sumColor = sumWeight * oriColor;
    vec2 uv = textureCoord;
    for (int i = 1; i <= MAX_SAMPLE; i++) {
        float k = float(i);
        if (k > u_sampleY) {
            break;
        }
        float y = k * u_stepY;
        uv.y = textureCoord.y - y;
        if (uv.y > 0.) {
            vec4 color = texture2D(inputImageTexture, uv);
            vec4 weight = getBilateralWeight(y, oriColor - color, spaceFactor, colorFactor);
            sumColor += weight * color;
            sumWeight += weight;
        }
        uv.y = textureCoord.y + y;
        if (uv.y < 1.) {
            vec4 color = texture2D(inputImageTexture, uv);
            vec4 weight = getBilateralWeight(y, oriColor - color, spaceFactor, colorFactor);
            sumColor += weight * color;
            sumWeight += weight;
        }
    }
    sumColor /= sumWeight;
    gl_FragColor = sumColor;
}
