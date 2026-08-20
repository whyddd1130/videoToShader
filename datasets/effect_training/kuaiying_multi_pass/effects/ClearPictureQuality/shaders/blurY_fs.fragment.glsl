#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D u_blurMidTexture;

uniform float u_sampleY;
uniform float u_sigmaY;
uniform float u_dy;
uniform int u_borderType;
uniform float u_strength;

#define TRUE 1
#define BORDER_TYPE_REPLICATE 1
#define BORDER_TYPE_BLACK 2
#define BORDER_TYPE_REFLECT 3
#define MAX_SAMPLE 1024
const float Eps = 1e-5;
float getGaussianWeight(float x, float sigma)
{
    return exp(-0.5 * x * x / (sigma * sigma));
}
void main()
{
    vec4 blurMidColor = texture2D(u_blurMidTexture, textureCoord);
    vec4 sumColor = blurMidColor;

    if (u_sampleY > Eps) {
        float sumWeight = getGaussianWeight(0., u_sigmaY);
        sumColor = sumWeight * blurMidColor;
        vec2 uv = textureCoord;
        for (int i = 1; i <= MAX_SAMPLE; i++) {
            float k = float(i);
            if (k > u_sampleY) {
                break;
            }

            float y = k * u_dy;
            float weight = getGaussianWeight(y, u_sigmaY);
            uv.y = textureCoord.y - y;
            if (uv.y < 0.) {
                if (u_borderType == BORDER_TYPE_REPLICATE) {
                    uv.y = 0.;
                    sumColor += weight * texture2D(u_blurMidTexture, uv);
                    sumWeight += weight;
                } else if (u_borderType == BORDER_TYPE_BLACK) {
                    sumColor += weight * vec4(0., 0., 0., 1.);
                    sumWeight += weight;
                } else if (u_borderType == BORDER_TYPE_REFLECT) {
                    uv.y = -uv.y;
                    sumColor += weight * texture2D(u_blurMidTexture, uv);
                    sumWeight += weight;
                }
            } else {
                sumColor += weight * texture2D(u_blurMidTexture, uv);
                sumWeight += weight;
            }
            uv.y = textureCoord.y + y;
            if (uv.y > 1.) {
                if (u_borderType == BORDER_TYPE_REPLICATE) {
                    uv.y = 1.;
                    sumColor += weight * texture2D(u_blurMidTexture, uv);
                    sumWeight += weight;
                } else if (u_borderType == BORDER_TYPE_BLACK) {
                    sumColor += weight * vec4(0., 0., 0., 1.);
                    sumWeight += weight;
                } else if (u_borderType == BORDER_TYPE_REFLECT) {
                    uv.y = 2. - uv.y;
                    sumColor += weight * texture2D(u_blurMidTexture, uv);
                    sumWeight += weight;
                }
            } else {
                sumColor += weight * texture2D(u_blurMidTexture, uv);
                sumWeight += weight;
            }
        }
        sumColor /= sumWeight;
    }
    vec4 oriColor = texture2D(inputImageTexture, textureCoord);
    sumColor.a = oriColor.a;
    sumColor.rgb = oriColor.rgb * (1. + u_strength) - sumColor.rgb * u_strength;
    gl_FragColor = clamp(sumColor, 0., 1.);
}
