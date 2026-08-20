#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float u_sampleX;
uniform float u_sigmaX;
uniform float u_dx;
uniform int u_borderType;

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
    if (u_sampleX < Eps) {
        gl_FragColor = texture2D(inputImageTexture, textureCoord);
        return;
    }
    vec4 oriColor = texture2D(inputImageTexture, textureCoord);
    float sumWeight = getGaussianWeight(0., u_sigmaX);
    vec4 sumColor = sumWeight * oriColor;

    vec2 uv = textureCoord;
    for (int i = 1; i <= MAX_SAMPLE; i++) {
        float k = float(i);
        if (k > u_sampleX) {
            break;
        }

        float x = k * u_dx;
        float weight = getGaussianWeight(x, u_sigmaX);

        uv.x = textureCoord.x - x;
        if (uv.x < 0.) {
            if (u_borderType == BORDER_TYPE_REPLICATE) {
                uv.x = 0.;
                sumColor += weight * texture2D(inputImageTexture, uv);
                sumWeight += weight;
            } else if (u_borderType == BORDER_TYPE_BLACK) {
                sumColor += weight * vec4(0., 0., 0., 1.);
                sumWeight += weight;
            } else if (u_borderType == BORDER_TYPE_REFLECT) {
                uv.x = -uv.x;
                sumColor += weight * texture2D(inputImageTexture, uv);
                sumWeight += weight;
            }
        } else {
            sumColor += weight * texture2D(inputImageTexture, uv);
            sumWeight += weight;
        }
        uv.x = textureCoord.x + x;
        if (uv.x > 1.) {
            if (u_borderType == BORDER_TYPE_REPLICATE) {
                uv.x = 1.;
                sumColor += weight * texture2D(inputImageTexture, uv);
                sumWeight += weight;
            } else if (u_borderType == BORDER_TYPE_BLACK) {
                sumColor += weight * vec4(0., 0., 0., 1.);
                sumWeight += weight;
            } else if (u_borderType == BORDER_TYPE_REFLECT) {
                uv.x = 2. - uv.x;
                sumColor += weight * texture2D(inputImageTexture, uv);
                sumWeight += weight;
            }
        } else {
            sumColor += weight * texture2D(inputImageTexture, uv);
            sumWeight += weight;
        }
    }
    sumColor /= sumWeight;
    gl_FragColor = sumColor;
}
