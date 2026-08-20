#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

vec4 texture2D_yFlip(float flip, sampler2D sampler, vec2 uv);
vec4 texture2D_yFlip(float flip, sampler2D sampler, vec2 uv, float bias);

//varying vec2 uv0;//替换为vTextureCoordinates
varying vec2 vTextureCoordinates;

uniform sampler2D inputImageTexture;
uniform sampler2D inputImageTexture1;
uniform int imageWidth;
uniform int imageHeight;
uniform int comicType;
uniform vec3 color1;
uniform vec3 color2;
uniform float gridNumRatio;


vec4 u_is_texture_0_flip_ = vec4(0.0,0.0,0.0,0.0); //vec4(1,0,0,0)

#define W vec3(0.299,0.587,0.114)

vec2 rotate(vec2 videoImageCoord,vec2 centerImageCoord,float radianAngle)
{
    vec2 rotateCenter = centerImageCoord;
    float rotateAngle = radianAngle ;
    float cos=cos(rotateAngle);
    float sin=sin(rotateAngle);
    mat3 rotateMat=mat3(cos,-sin,0.0,
    sin,cos,0.0,
    0.0,0.0,1.0);
    vec3 deltaOffset;
    deltaOffset = rotateMat*vec3(videoImageCoord.x- rotateCenter.x,videoImageCoord.y- rotateCenter.y,1.0);
    videoImageCoord.x = deltaOffset.x+rotateCenter.x;
    videoImageCoord.y = deltaOffset.y+rotateCenter.y;
    return videoImageCoord;
}

float lm_rgb2gray(vec3 rgb)
{
    float gray = dot(rgb,W);
    return gray;
}

vec4 lm_edge_sobel(float p_is_inputImageTex_flip_, sampler2D inputImageTex,vec2 uv0,vec2 stepScale,int imageWidth,int imageHeight)
{
    vec4 n[9];
    float w = 1.0/float(imageWidth)*stepScale.x;
    float h = 1.0/float(imageHeight)*stepScale.y;
    n[0] = texture2D_yFlip(p_is_inputImageTex_flip_, inputImageTex, uv0 + vec2( -w, -h));
    n[1] = texture2D_yFlip(p_is_inputImageTex_flip_, inputImageTex, uv0 + vec2(0.0, -h));
    n[2] = texture2D_yFlip(p_is_inputImageTex_flip_, inputImageTex, uv0 + vec2(  w, -h));
    n[3] = texture2D_yFlip(p_is_inputImageTex_flip_, inputImageTex, uv0 + vec2( -w, 0.0));
    n[4] = texture2D_yFlip(p_is_inputImageTex_flip_, inputImageTex, uv0);
    n[5] = texture2D_yFlip(p_is_inputImageTex_flip_, inputImageTex, uv0 + vec2(  w, 0.0));
    n[6] = texture2D_yFlip(p_is_inputImageTex_flip_, inputImageTex, uv0 + vec2( -w, h));
    n[7] = texture2D_yFlip(p_is_inputImageTex_flip_, inputImageTex, uv0 + vec2(0.0, h));
    n[8] = texture2D_yFlip(p_is_inputImageTex_flip_, inputImageTex, uv0 + vec2(  w, h));

    vec4 sobel_edge_h = n[2] + (2.0*n[5]*1.0) + n[8] - (n[0] + (2.0*n[3]*1.0) + n[6]);
    vec4 sobel_edge_v = n[0] + (2.0*n[1]*1.0) + n[2] - (n[6] + (2.0*n[7]*1.0) + n[8]);
    vec4 sobel = sqrt((sobel_edge_h * sobel_edge_h) + (sobel_edge_v * sobel_edge_v));

    float gray = lm_rgb2gray(sobel.rgb);
    sobel = vec4(vec3(gray),1.0);

    return sobel;
}


vec4 lm_black_white_comic()
{
    vec2 stepScale = vec2(1.0,1.0);
    vec4 srcColor = texture2D_yFlip(u_is_texture_0_flip_[0], inputImageTexture,vTextureCoordinates);
    vec4 blurColor = texture2D_yFlip(u_is_texture_0_flip_[1], inputImageTexture1,vTextureCoordinates);
    vec4 maskColor = lm_edge_sobel(u_is_texture_0_flip_[1], inputImageTexture1,vTextureCoordinates,stepScale,imageWidth,imageHeight);
    vec4 resultColor = pow(maskColor,vec4(0.9985));
    resultColor.rgb = step(0.7875,1.0-resultColor.rgb);
    resultColor.a = 1.0;
    return resultColor;
}


vec4 lm_dot_effect(int type)
{
    vec2 screenSize = vec2(imageWidth,imageHeight);
    vec2 uv00 = vTextureCoordinates*screenSize;
    vec2 center = vec2(0.5)*screenSize;
    uv00 = rotate(uv00,center,-0.15);
    uv00 /= screenSize;
    vec2 grid_num = screenSize*gridNumRatio;//0.12
    vec2 uv1 = uv00*grid_num;
    vec2 uv2 = fract(uv1);
    vec2 uv3 = floor(uv1)/grid_num;
    vec2 uv = uv2;
//    vec4 redColor = vec4(vec3(233.0,51.0,35.0)/255.0,1.0);
//    vec4 yellowColor = vec4(vec3(255.0,255.0,84.0)/255.0,1.0);
    vec4 redColor = vec4(color1,1.0);
    vec4 yellowColor = vec4(color2,1.0);
    vec4 blackColor = vec4(0.0,0.0,0.0,1.0);
    vec4 resultColor = vec4(1.0);
    float dis = distance(uv,vec2(0.5));
    if(type==1)
    {
        resultColor = dis<0.3?redColor:yellowColor;
    }
    else if(type==2)
    {
        resultColor = dis<0.3?yellowColor:redColor;
    }
    else if(type==3)
    {

        vec4 prop = vec4(0.950,0.920,0.0,1.0);
        resultColor = dis<0.13?prop:blackColor;
    }

    return resultColor;
}


vec4 lm_colourful_comic()
{

    vec4 srcColor = texture2D_yFlip(u_is_texture_0_flip_[1], inputImageTexture1,vTextureCoordinates);
    vec4 resultColor = srcColor;
    float gray = dot(srcColor.rgb,W);
    float stage = 1.0/4.0;
    if(gray<stage)
    resultColor = lm_dot_effect(3);
    else if(gray<2.0*stage)
    resultColor = lm_dot_effect(2);
    else if(gray<3.0*stage)
    resultColor = lm_dot_effect(1);
    else
    resultColor = vec4(1.0);

    vec4 comicColor = lm_black_white_comic();
    resultColor = mix(comicColor,resultColor,comicColor.r);

    resultColor.a = 1.0;
    return resultColor;
}

vec4 lm_colourful_comic_to_gray()
{
    vec4 srcColor = lm_colourful_comic();
    float m_gray = lm_rgb2gray(srcColor.rgb);
    vec4 resultColor = vec4(vec3(m_gray),1.0);
    return resultColor;
}


vec4 texture2D_yFlip(float flip, sampler2D sampler, vec2 uv)
{
//    if (flip > 0.5)
//    {
//        uv.y = 1.0 - uv.y;
//    }
    return texture2D(sampler, uv);
}
vec4 texture2D_yFlip(float flip, sampler2D sampler, vec2 uv, float bias)
{
    return texture2D(sampler, uv, bias);
}
void main(void)
{
//    vec4 blurColor = texture2D_yFlip(u_is_texture_0_flip_[1], inputImageTexture1,vTextureCoordinates);
//    vec4 resultColor = blurColor;
//    resultColor = lm_colourful_comic_to_gray();
//    vec4 resultColor = lm_colourful_comic();

    vec4 resultColor = vec4(1.0,1.0,1.0,1.0);
    if(comicType == 1)
    {
        resultColor = lm_colourful_comic_to_gray();
    }else
    {
        resultColor = lm_colourful_comic();
    }

    gl_FragColor = resultColor;
}
