#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform float blurSize;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
vec4 enCode(float a){
    float a1 = floor(a*255.);
    float b1 = fract(a*255.);
    float a2 = floor(b1*255.);
    float b2 = fract(b1*255.);
    float a3 = floor(b2*255.);
    float b3 = fract(b2*255.);
    return vec4(a1/255.,a2/255.,a3/255.,b3);
}
float deCode(vec4 a){
    return a.x+a.y/255.+a.z/(255.*255.)+a.w/(255.*255.*255.);
}
void main()
{
    vec2 offset = vec2(0.0, 1.0)*vec2(blurSize)/u_ScreenParams.xy;

    float weight0 = normpdf(0.0,25.);
    float resultGray = deCode(texture2D(inputImageTexture, textureCoord))*weight0;
    float num = weight0;
    for(int i = 1 ;i <= 50 ;i++){
        float j = float(i);
        float tempWeight = normpdf(j,25.);
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord + j*offset))*tempWeight;
        resultGray+=deCode(texture2D(inputImageTexture, textureCoord - j*offset))*tempWeight;
        num+=2.0*tempWeight;
    }
    resultGray/=num;
    gl_FragColor = vec4(enCode(resultGray));
}
