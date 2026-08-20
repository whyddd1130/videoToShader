precision highp float;


uniform float uProgress;
uniform float uTime;
uniform sampler2D inputImageTexture;
varying vec2 uv;
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define blurSize (1.0 + 34.0 * uProgress)
void main()
{
    vec2 mySize = u_ScreenParams.xy/min(u_ScreenParams.x,u_ScreenParams.y)*720.;
    vec2 offset = vec2(0.0,1.)*vec2(blurSize)/mySize;

    float half_gaussian_weight[9];
    
    half_gaussian_weight[0]= 0.30;
    half_gaussian_weight[1]= 0.25;
    half_gaussian_weight[2]= 0.2;
    half_gaussian_weight[3]= 0.18;
    half_gaussian_weight[4]= 0.16;
    half_gaussian_weight[5]= 0.15;
    half_gaussian_weight[6]= 0.1;
    half_gaussian_weight[7]= 0.05;
    half_gaussian_weight[8]= 0.02;
    vec4 resultCol = texture2D(inputImageTexture, uv);
    float num = 1.0;
    for(int i = 1 ;i <= 8 ;i++){
        float j = float(i);
        resultCol+= texture2D(inputImageTexture, uv+j*offset);
        resultCol+= texture2D(inputImageTexture, uv-j*offset);
        num+=2.0;
    }
    resultCol/=num;

    gl_FragColor = vec4(resultCol);
}
