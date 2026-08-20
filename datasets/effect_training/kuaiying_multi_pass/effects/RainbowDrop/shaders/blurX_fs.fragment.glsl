#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D sdfTexture;

uniform vec2 screenParams;
uniform float iTime;
uniform float blurSize;

vec2 lowPrecision(vec4 myuv)
{
    return myuv.xy + myuv.zw / 255.;
}

void main()
{
    float half_gaussian_weight[9];
    half_gaussian_weight[0] = 0.20;
    half_gaussian_weight[1] = 0.19;
    half_gaussian_weight[2] = 0.17;
    half_gaussian_weight[3] = 0.15;
    half_gaussian_weight[4] = 0.13;
    half_gaussian_weight[5] = 0.11;
    half_gaussian_weight[6] = 0.08;
    half_gaussian_weight[7] = 0.05;
    half_gaussian_weight[8] = 0.02;
    
    float ratioFlag = smoothstep(1.0,1.777,max(screenParams.x,screenParams.y)/min(screenParams.x,screenParams.y));
    vec2 uv1 = (textureCoord-0.5)*mix(1.0,0.76,smoothstep(0.0,0.2,iTime)*smoothstep(1.2+0.3*ratioFlag,0.2,iTime))+0.5;
    vec4 col = texture2D(inputImageTexture, uv1)*half_gaussian_weight[0];
    float num = half_gaussian_weight[0];

    vec4 sdfCol = texture2D(sdfTexture,textureCoord);
    vec2 sdfVec = lowPrecision(sdfCol);
    float d = sdfVec.x-sdfVec.y;
    vec2 offset = vec2(blurSize,0.0)/screenParams.xy*smoothstep(-0.03,0.03,d);

    for(int i= 1;i<=8;i++)
    {
        float j = float(i);
        vec2 tempUV = uv1-offset*j;
        vec4 res_r = texture2D(inputImageTexture, tempUV);
        col+=res_r*half_gaussian_weight[i];
        tempUV = uv1+offset*j;
        res_r = texture2D(inputImageTexture, tempUV);
        col+=res_r*half_gaussian_weight[i];
        num+=2.0*half_gaussian_weight[i];
    }
    col /= num;
    col.rgb *= mix(0.8, 1.0, smoothstep(0.0, 1.0, iTime));
    gl_FragColor = col;
}
