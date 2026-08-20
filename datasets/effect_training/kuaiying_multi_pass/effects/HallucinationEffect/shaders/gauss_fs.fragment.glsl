#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float u_sample;
uniform float u_baseTexWidth;
uniform float u_baseTexHeight;
uniform vec2 blurDir;

float normpdf(in float x, in float sigma)
{
    return 0.39894 * exp(-0.5 * x * x / (sigma * sigma)) / sigma;
}
vec4 gaussianBlur(sampler2D i_InputTex, vec2 i_Uv, vec2 i_Dir, vec2 screenSize)
{
    float sigma = 4.0;
    float weight = normpdf(0.0, sigma);

    vec4 sum = vec4(0.0);
    vec4 result = vec4(0.0);
    vec2 unit_uv = i_Dir / screenSize;
    float gamma = 1.0;
    vec4 curColor = texture2D(i_InputTex, i_Uv);
    vec4 centerPixel = pow(curColor, vec4(gamma)) * weight;
    float sum_weight = weight;

    float s = u_sample;
    for (int i = 1; i <= 1024; i++) {
        if (float(i) > u_sample) {
            break;
        }
        vec2 curRightCoordinate = i_Uv + float(i) * unit_uv;
        vec2 curLeftCoordinate = i_Uv + float(-i) * unit_uv;
        vec4 rightColor = texture2D(i_InputTex, curRightCoordinate);
        vec4 leftColor = texture2D(i_InputTex, curLeftCoordinate);
        weight = normpdf(float(i) / s * 15.0, sigma);
        sum += pow(rightColor, vec4(gamma)) * weight;
        sum += pow(leftColor, vec4(gamma)) * weight;
        sum_weight += weight * 2.0;
    }

    result = (sum + centerPixel) / sum_weight;
    result = pow(result, vec4(1.0 / gamma));
    return clamp(result, 0.0, 1.0);
}
void main()
{
    vec2 screenSize = vec2(u_baseTexWidth, u_baseTexHeight) / min(u_baseTexWidth, u_baseTexHeight) * 720.;
    gl_FragColor = gaussianBlur(inputImageTexture, textureCoord, blurDir, screenSize);
}
