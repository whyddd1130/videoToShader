#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 radius;
uniform vec2 screenParams;

vec2 Mirror(vec2 _u)
{
    return abs(mod(_u-1.,2.)-1.);
}

float gaussianWeight(float dist, float stdDev)
{
    return exp(-dist / (2.0 * stdDev));
}

vec4 gaussianBlur(sampler2D inputTexture, vec2 textureCoordinate, vec2 stepUV, vec2 screenSize)
{
    const int blurRadius = 20;
    vec2 unitUV         = vec2(stepUV.x, stepUV.y*screenSize.x/screenSize.y)/720.;
    float stdDev        = 112.0;
    float sumWeight     = gaussianWeight(0.0,stdDev);
    vec4 curColor       = texture2D(inputTexture, textureCoordinate);    
    vec4 sumColor       = curColor*sumWeight;
    //horizontal
    for(int i=1;i<=blurRadius;i++)
    {
        vec2 textureCoordinateA = textureCoordinate+float(i)*unitUV;
        vec2 textureCoordinateB = textureCoordinate+float(-i)*unitUV;
        vec4 colorA = texture2D(inputTexture, Mirror(textureCoordinateA));
        vec4 colorB = texture2D(inputTexture, Mirror(textureCoordinateB));
        float curWeight = gaussianWeight(float(i),stdDev);
        sumColor += colorA*curWeight;
        sumColor += colorB*curWeight;
        sumWeight+= curWeight*2.0;
    }

    vec4 resultColor = sumColor/sumWeight;
    return resultColor;
}

void main()
{
    vec2 uv1 = textureCoord;
    vec4 res = texture2D(inputImageTexture, uv1);

    vec4 res_v = gaussianBlur(inputImageTexture, uv1, vec2(radius.x,0), screenParams.xy);
    vec4 res_h = gaussianBlur(inputImageTexture, uv1, vec2(0,radius.y), screenParams.xy);
    res = res_v * 0.5 + res_h * 0.5;

    gl_FragColor = res;
}
