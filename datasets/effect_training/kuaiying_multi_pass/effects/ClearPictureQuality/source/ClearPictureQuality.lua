
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

---@language GLSL
local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
varying vec2 textureCoord;

void main()
{
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

---@language GLSL
local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

void main() 
{
    gl_FragColor = texture2D(inputImageTexture, textureCoord);
}
]]

---@language GLSL
local threshold_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float u_threshold;
uniform float u_thresholdSmooth;

float softLightf(float s, float d)
{
    return (s < 0.5) ? d - (1.0 - 2.0 * s) * d * (1.0 - d) 
        : (d < 0.25) ? d + (2.0 * s - 1.0) * d * ((16.0 * d - 12.0) * d + 3.0) 
                     : d + (2.0 * s - 1.0) * (sqrt(d) - d);
}
vec3 BlendSoftLight(vec3 s, vec3 d)
{
    return vec3(softLightf(s.r, d.r), softLightf(s.g, d.g), softLightf(s.b, d.b));
}
void main()
{
    vec4 inputColor = texture2D(inputImageTexture, textureCoord);
    vec4 thrColor = vec4(step(vec3(u_threshold), inputColor.rgb), 1.0);
    thrColor.a = clamp(thrColor.r + thrColor.g + thrColor.b, 0.0, 1.0);
    vec4 blendColor = vec4(BlendSoftLight(thrColor.rgb * inputColor.rgb, inputColor.rgb * u_thresholdSmooth), softLightf(thrColor.a * inputColor.a, inputColor.a * u_thresholdSmooth));
    thrColor = thrColor * inputColor + blendColor * (1.0 - thrColor);
    gl_FragColor = thrColor;
}
]]

---@language GLSL
local gauss_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float u_Angle;
uniform float u_Strength;
uniform vec2 u_ScreenParams;
uniform float u_DownSample;
uniform float u_gamma;
float normpdf(in float x, in float sigma)
{
	return exp(-0.5*x*x/(sigma*sigma));
}

vec4 gaussianBlur(sampler2D i_InputTex, vec2 i_Uv, vec2 i_Dir, float i_Strength)
{
    float sigma = 4.0;
    float first = normpdf(0.0, sigma);
    float weight = 0.5 * 1.02 + 0.5;
    weight = first;
    vec4 sum            = vec4(0.0);
    vec4 result         = vec4(0.0);
    vec2 unit_uv        = i_Dir * u_DownSample;
    vec4 curColor       = texture2D(i_InputTex, i_Uv);
    float gamma = u_gamma; 
    vec4 center = pow(curColor, vec4(gamma)) * weight;
    vec4 sum_weight = vec4(weight);
    float s = i_Strength;
    for(int i=1;i<=1000;++i)
    {
        if (float(i) > i_Strength) break;
        float curIndex = float(i);
        vec2 curRightCoordinate = i_Uv+float(i)*unit_uv;
        vec2 curLeftCoordinate  = i_Uv+float(-i)*unit_uv;
        vec4 rightColor = texture2D(i_InputTex, curRightCoordinate);
        vec4 leftColor = texture2D(i_InputTex, curLeftCoordinate);
        rightColor = pow(rightColor, vec4(gamma));
        leftColor = pow(leftColor, vec4(gamma));
        weight = normpdf(curIndex / s * 16.0, sigma);
        sum += (rightColor + leftColor) * weight;
        sum_weight.a += weight * 2.0;
    }
    result = (sum + center) / sum_weight.a;
    return pow(result, vec4(1.0 / gamma));
}

void main()
{
    float theta = u_Angle / 180.0 * 3.1415926;
    vec2 ratio = 720.0 * u_ScreenParams.xy / min(u_ScreenParams.x, u_ScreenParams.y);
    vec2 dir = vec2(cos(theta), sin(theta)) / ratio.xy;
    vec4 color = gaussianBlur(inputImageTexture, textureCoord, dir, u_Strength);
    gl_FragColor = color;
}
]]

---@language GLSL
local glow_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D u_GlowBlurTex1;
uniform sampler2D u_GlowBlurTex2;
uniform sampler2D u_GlowBlurTex3;
uniform sampler2D u_GlowBlurTex4;
uniform sampler2D u_GlowBlurTex5;
uniform sampler2D u_GlowBlurTex6;
uniform sampler2D u_GlowBlurTex7;
uniform sampler2D u_GlowBlurTex8;
uniform float u_GlowIntensity;
uniform float u_gamma;
uniform int u_blendType;
void main()
{
    float gamma = u_gamma;
    vec4 oriColor = texture2D(inputImageTexture, textureCoord);
    vec4 blurColor1 = texture2D(u_GlowBlurTex1, textureCoord);
    vec4 blurColor2 = texture2D(u_GlowBlurTex2, textureCoord);
    vec4 blurColor3 = texture2D(u_GlowBlurTex3, textureCoord);
    vec4 blurColor4 = texture2D(u_GlowBlurTex4, textureCoord);
    vec4 blurColor5 = texture2D(u_GlowBlurTex5, textureCoord);
    vec4 blurColor6 = texture2D(u_GlowBlurTex6, textureCoord);
    vec4 blurColor7 = texture2D(u_GlowBlurTex7, textureCoord);
    vec4 blurColor8 = texture2D(u_GlowBlurTex8, textureCoord);
    float intensity = u_GlowIntensity;
    vec4 dis1 = clamp(blurColor1, 0.0, 1.0);
    vec4 dis2 = clamp(blurColor2, 0.0, 1.0);
    vec4 dis3 = clamp(blurColor3, 0.0, 1.0);
    vec4 dis4 = clamp(blurColor4, 0.0, 1.0);
    vec4 dis5 = clamp(blurColor5, 0.0, 1.0);
    vec4 dis6 = clamp(blurColor6, 0.0, 1.0);
    vec4 dis7 = clamp(blurColor7, 0.0, 1.0);
    vec4 dis8 = clamp(blurColor8, 0.0, 1.0);
    dis1 = pow(dis1, vec4(gamma));
    dis2 = pow(dis2, vec4(gamma));
    dis3 = pow(dis3, vec4(gamma));
    dis4 = pow(dis4, vec4(gamma));
    dis5 = pow(dis5, vec4(gamma));
    dis6 = pow(dis6, vec4(gamma));
    dis7 = pow(dis7, vec4(gamma));
    dis8 = pow(dis8, vec4(gamma));

    vec4 glowColor = vec4(0.0);
    if (u_blendType == 0) {
        dis1 = 1. - (1. - dis1) * (1. - dis2);
        dis1 = 1. - (1. - dis1) * (1. - dis3);
        dis1 = 1. - (1. - dis1) * (1. - dis4);
        dis1 = 1. - (1. - dis1) * (1. - dis5);
        dis1 = 1. - (1. - dis1) * (1. - dis6);
        dis1 = 1. - (1. - dis1) * (1. - dis7);
        dis1 = 1. - (1. - dis1) * (1. - dis8);
        glowColor = pow(dis1 * intensity, vec4(1.0/gamma));
        glowColor = clamp(glowColor, 0.0, 1.0);
        oriColor = (1. - (1. - glowColor) * (1. - oriColor));
    }
    else {
        dis1 = dis1 + dis2;
        dis1 = dis1 + dis3;
        dis1 = dis1 + dis4;
        dis1 = dis1 + dis5;
        dis1 = dis1 + dis6;
        dis1 = dis1 + dis7;
        dis1 = dis1 + dis8;
        glowColor = pow(dis1 * intensity, vec4(1.0/gamma));
        glowColor = clamp(glowColor, 0.0, 1.0);
        oriColor = glowColor + oriColor;
    }
    gl_FragColor = oriColor;
}
]]

---@language GLSL
local blend_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D u_SourceTexture;
uniform sampler2D u_BaseTexure;
uniform int u_BlendMode;
uniform int u_NeedBlend;
uniform int u_layerType;

#define LAYER_TYPE_ADJUSTMENT 1
#define BLEND_MODE_NORMAL 0

float random(vec2 st)
{
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

#define BlendOverlayf(s, d)      (d < 0.5 ? (2.0 * d * s) : (1.0 - 2.0 * (1.0 - d) * (1.0 - s))) 
#define BlendOverlay(s, d)       vec3(BlendOverlayf(s.r, d.r), BlendOverlayf(s.g, d.g), BlendOverlayf(s.b, d.b))
#define BlendScreen(s, d)        (s + d - s * d)
#define BlendMultiply(s, d)      (s * d)
#define BlendDifference(s, d)    (abs(s - d))
#define BlendAdd(s, d)           (s + d)
#define BlendSubtract(s, d)      max(vec3(0.0), (d - s))
#define BlendDarken(s, d)        min(s, d)
#define BlendLighten(s, d)       max(s, d)
#define BlendExclusion(s, d)     (d + s - 2.0 * d * s)

float softLightf(float s, float d)
{
    return (s < 0.5) ? d - (1.0 - 2.0 * s) * d * (1.0 - d) : (d < 0.25) ? d + (2.0 * s - 1.0) * d * ((16.0 * d - 12.0) * d + 3.0) : d + (2.0 * s - 1.0) * (sqrt(d) - d);
}
vec3 BlendSoftLight(vec3 s, vec3 d)
{
    return vec3(softLightf(s.r, d.r), softLightf(s.g, d.g), softLightf(s.b, d.b));
}

float hardLightf(float s, float d)
{
    return (s < 0.5) ? 2.0 * s * d : 1.0 - 2.0 * (1.0 - s) * (1.0 - d);
}
vec3 BlendHardLight(vec3 s, vec3 d)
{
    return vec3(hardLightf(s.r, d.r), hardLightf(s.g, d.g), hardLightf(s.b, d.b));
}

float getLuminosity(vec3 color)
{
    return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 setLuminosity(vec3 c, float lum)
{
    float d = lum - getLuminosity(c);
    c.rgb += vec3(d);

    // clip back into legal range
    lum = getLuminosity(c);
    float cMin = min(c.r, min(c.g, c.b));
    float cMax = max(c.r, max(c.g, c.b));

    if (cMin < 0.0)
        c = mix(vec3(lum, lum, lum), c, lum / (lum - cMin));

    if (cMax > 1.0)
        c = mix(vec3(lum, lum, lum), c, (1. - lum) / (cMax - lum));

    return c;
}

vec3 setSaturationMinMidMax(vec3 cSorted, float s)
{
    if (cSorted.z > cSorted.x)
    {
        cSorted.y = (((cSorted.y - cSorted.x) * s) / (cSorted.z - cSorted.x));
        cSorted.z = s;
    }
    else
    {
        cSorted.y = 0.0;
        cSorted.z = 0.0;
    }

    cSorted.x = 0.0;

    return cSorted;
}

float getSaturation(vec3 c)
{
    return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
}

vec3 setSaturation(vec3 c, float s)
{
    if (c.r <= c.g && c.r <= c.b)
    {
        if (c.g <= c.b)
            c.rgb = setSaturationMinMidMax(c.rgb, s);
        else
            c.rbg = setSaturationMinMidMax(c.rbg, s);
    }
    else if (c.g <= c.r && c.g <= c.b)
    {
        if (c.r <= c.b)
            c.grb = setSaturationMinMidMax(c.grb, s);
        else
            c.gbr = setSaturationMinMidMax(c.gbr, s);
    }
    else
    {
        if (c.r <= c.g)
            c.brg = setSaturationMinMidMax(c.brg, s);
        else
            c.bgr = setSaturationMinMidMax(c.bgr, s);
    }

    return c;
}

vec3 BlendHue(vec3 s, vec3 d)
{
    return setLuminosity(setSaturation(s, getSaturation(d)), getLuminosity(d));
}

vec3 BlendSaturation(vec3 s, vec3 d)
{
    return setLuminosity(setSaturation(d, getSaturation(s)), getLuminosity(d));
}

vec3 BlendColor(vec3 s, vec3 d)
{
    return setLuminosity(s, getLuminosity(d));
}

vec3 BlendDarkerColor(vec3 s, vec3 d)
{
    return getLuminosity(d) <= getLuminosity(s) ? d : s;
}

vec3 BlendLighterColor(vec3 s, vec3 d)
{
    return getLuminosity(d) > getLuminosity(s) ? d : s;
}

vec3 BlendLuminosity(vec3 s, vec3 d)
{
    return setLuminosity(d, getLuminosity(s));
}

float colorBurn(float s, float d)
{
    if (d >= 1.0)
        return 1.0;
    else if (s <= 0.0)
        return 0.0;
    else
        return 1.0 - min(1.0, (1.0 - d) / s);
}
vec3 BlendColorBurn(vec3 s, vec3 d)
{
    return vec3(colorBurn(s.r, d.r), colorBurn(s.g, d.g), colorBurn(s.b, d.b));
}

float linearBurn(float s, float d)
{
    return max(0.0, d + s - 1.0);
}
vec3 BlendLinearBurn(vec3 s, vec3 d)
{
    return vec3(linearBurn(s.r, d.r), linearBurn(s.g, d.g), linearBurn(s.b, d.b));
}

float colorDodge(float s, float d)
{
    if (d <= 0.0)
        return 0.0;
    if (s >= 1.0)
        return 1.0;
    else
        return min(1.0, d / (1.0 - s));
}
vec3 BlendColorDodge(vec3 s, vec3 d)
{
    return vec3(colorDodge(s.r, d.r), colorDodge(s.g, d.g), colorDodge(s.b, d.b));
}

float linearDodge(float s, float d)
{
    return min(1.0, d + s);
}
vec3 BlendLinearDodge(vec3 s, vec3 d)
{
    return vec3(linearDodge(s.r, d.r), linearDodge(s.g, d.g), linearDodge(s.b, d.b));
}

float vividLight(float s, float d)
{
    return (s <= 0.5) ? colorBurn(d, 2.0 * s) : colorDodge(d, 2.0 * (s - 0.5));
}
vec3 BlendVividLight(vec3 s, vec3 d)
{
    return vec3(vividLight(s.r, d.r), vividLight(s.g, d.g), vividLight(s.b, d.b));
}

float linearLight(float s, float d)
{
    return (s <= 0.5) ? linearBurn(d, 2.0 * s) : linearDodge(d, 2.0 * (s - 0.5));
}
vec3 BlendLinearLight(vec3 s, vec3 d)
{
    return vec3(linearLight(s.r, d.r), linearLight(s.g, d.g), linearLight(s.b, d.b));
}

float pinLight(float s, float d)
{
    return (s <= 0.5) ? min(d, 2.0 * s) : max(d, 2.0 * (s - 0.5));
}
vec3 BlendPinLight(vec3 s, vec3 d)
{
    return vec3(pinLight(s.r, d.r), pinLight(s.g, d.g), pinLight(s.b, d.b));
}

float hardMix(float s, float d)
{
    return (d + s >= 1.0) ? 1.0 : 0.0;
}
vec3 BlendHardMix(vec3 s, vec3 d)
{
    return vec3(hardMix(s.r, d.r), hardMix(s.g, d.g), hardMix(s.b, d.b));
}

float divide(float s, float d)
{
    return s > 0.0 ? min(1.0, d / s) : 1.0;
}
vec3 BlendDivide(vec3 s, vec3 d)
{
    return vec3(divide(s.r, d.r), divide(s.g, d.g), divide(s.b, d.b));
}

void main()
{
    vec4 baseColor = texture2D(u_BaseTexure, textureCoord);
    if (u_NeedBlend == 0)
    {
        gl_FragColor = baseColor;
        return;
    }

    if (u_layerType == LAYER_TYPE_ADJUSTMENT && u_BlendMode == BLEND_MODE_NORMAL)
    {
        gl_FragColor = texture2D(u_SourceTexture, textureCoord);
        return;
    }

    vec4 srcColor = texture2D(u_SourceTexture, textureCoord);
    srcColor.rgb /= (srcColor.a + 0.0001);
    baseColor.rgb /= (baseColor.a + 0.0001);

    vec4 blendColor = baseColor;
    if (u_BlendMode == 1)
    {
        blendColor.rgb = BlendAdd(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 2)
    {
        blendColor.rgb = BlendMultiply(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 3)
    {
        blendColor.rgb = BlendDifference(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 4)
    {
        blendColor.rgb = BlendOverlay(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 5)
    {
        blendColor.rgb = BlendDarken(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 6)
    {
        blendColor.rgb = BlendLighten(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 7)
    {
        blendColor.rgb = BlendSoftLight(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 8)
    {
        blendColor.rgb = BlendHardLight(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 9)
    {
        blendColor.rgb = BlendHue(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 10)
    {
        blendColor.rgb = BlendSaturation(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 11)
    {
        blendColor.rgb = BlendColor(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 12)
    {
        blendColor.rgb = BlendScreen(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 13)
    {
        blendColor.rgb = BlendColorBurn(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 14)
    {
        blendColor.rgb = BlendLinearBurn(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 15)
    {
        blendColor.rgb = BlendColorDodge(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 16)
    {
        blendColor.rgb = BlendLinearDodge(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 17)
    {
        blendColor.rgb = BlendVividLight(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 18)
    {
        blendColor.rgb = BlendLinearLight(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 19)
    {
        blendColor.rgb = BlendPinLight(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 20)
    {
        blendColor.rgb = BlendHardMix(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 21)
    {
        blendColor.rgb = BlendExclusion(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 22)
    {
        blendColor.rgb = BlendSubtract(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 23)
    {
        blendColor.rgb = BlendDivide(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 24)
    {
        blendColor.rgb = BlendLuminosity(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 25)
    {
        blendColor.rgb = BlendLighterColor(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 26)
    {
        blendColor.rgb = BlendDarkerColor(srcColor.rgb, baseColor.rgb);
    }
    else if (u_BlendMode == 27) // Dissolve
    {
        if (srcColor.a == 1.0 || (srcColor.a > 0.0 && srcColor.a > random(textureCoord)))
        {
            blendColor.rgb = srcColor.rgb;
        }
    }
    else // normal
    {
        blendColor.rgb = srcColor.rgb;
    }

    vec4 result = vec4(0.);

    result.rgb = baseColor.rgb * baseColor.a * (1.0 - srcColor.a) +
        srcColor.rgb * srcColor.a * (1.0 - baseColor.a) +
        srcColor.a * baseColor.a * blendColor.rgb;
    result.a = srcColor.a + baseColor.a * (1.0 - srcColor.a);
    gl_FragColor = result;
}
]]

---@language GLSL
local bilateralBlurX_fs = [[
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
]]

---@language GLSL
local bilateralBlurY_fs = [[
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
]]

---@language GLSL
local blurX_fs = [[
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
]]

---@language GLSL
local blurY_fs = [[
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
]]

ClearPictureQuality = {}

function ClearPictureQuality:matchWithId(effectId)
    return 'KFM KSkr ClearPictureQuality' == effectId
end

function ClearPictureQuality.createWithId(effectId)
    if not ClearPictureQuality:matchWithId(effectId) then
        return nil
    end
    local o = {
        program1 = {},
        program2 = {},
        program3 = {},
        program4 = {},
        program5 = {},
        program6 = {},
        program7 = {},
        program8 = {},
        adjustLuminance = 0,
        adjustSharpen = 0,
        adjustBlur = 0,
        adjustRange = 0,
        adjustSize = 0,
        adjustSoft = 0,
        currentWidth = 0,
        currentHeight = 0
    }
    o = newObject(o, ClearPictureQuality)
    o:init()
    return o;
end

function ClearPictureQuality:init()
    self.program1 = CGE.ProgramObject()
    self.program1:bindAttribLocation('position', 0)
    self.program1:initWithShaderStrings(vs, threshold_fs)
    self.program1:bind()
    self.program1:sendUniformi('inputImageTexture', 0)

    self.program2 = CGE.ProgramObject()
    self.program2:bindAttribLocation('position', 0)
    self.program2:initWithShaderStrings(vs, gauss_fs)
    self.program2:bind()
    self.program2:sendUniformi('inputImageTexture', 0)

    self.program3 = CGE.ProgramObject()
    self.program3:bindAttribLocation('position', 0)
    self.program3:initWithShaderStrings(vs, glow_fs)
    self.program3:bind()
    self.program3:sendUniformi('inputImageTexture', 0)
    self.program3:sendUniformi('u_GlowBlurTex1', 1)
    self.program3:sendUniformi('u_GlowBlurTex2', 2)
    self.program3:sendUniformi('u_GlowBlurTex3', 3)
    self.program3:sendUniformi('u_GlowBlurTex4', 4)
    self.program3:sendUniformi('u_GlowBlurTex5', 5)
    self.program3:sendUniformi('u_GlowBlurTex6', 6)
    self.program3:sendUniformi('u_GlowBlurTex7', 7)
    self.program3:sendUniformi('u_GlowBlurTex8', 8)

    self.program4 = CGE.ProgramObject()
    self.program4:bindAttribLocation('position', 0)
    self.program4:initWithShaderStrings(vs, blend_fs)
    self.program4:bind()
    self.program4:sendUniformi('u_SourceTexture', 0)
    self.program4:sendUniformi('u_BaseTexure', 1)

    self.program5 = CGE.ProgramObject()
    self.program5:bindAttribLocation('position', 0)
    self.program5:initWithShaderStrings(vs, bilateralBlurX_fs)
    self.program5:bind()
    self.program5:sendUniformi('inputImageTexture', 0)

    self.program6 = CGE.ProgramObject()
    self.program6:bindAttribLocation('position', 0)
    self.program6:initWithShaderStrings(vs, bilateralBlurY_fs)
    self.program6:bind()
    self.program6:sendUniformi('inputImageTexture', 0)

    self.program7 = CGE.ProgramObject()
    self.program7:bindAttribLocation('position', 0)
    self.program7:initWithShaderStrings(vs, blurX_fs)
    self.program7:bind()
    self.program7:sendUniformi('inputImageTexture', 0)

    self.program8 = CGE.ProgramObject()
    self.program8:bindAttribLocation('position', 0)
    self.program8:initWithShaderStrings(vs, blurY_fs)
    self.program8:bind()
    self.program8:sendUniformi('inputImageTexture', 0)
    self.program8:sendUniformi('u_blurMidTexture', 1)

    local buffer = {}
    glGenBuffers(1,buffer) 
    self.vertexBuffer = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function ClearPictureQuality:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- AdjustLuminance *
        self.adjustLuminance = val1 / 100.0
    elseif index == 2 then
        -- AdjustSharpen *
        self.adjustSharpen = val1 / 100.0 * 2.0
    elseif index == 3 then
        -- AdjustBlur *
        self.adjustBlur = val1 / 100.0 * 1.5
    elseif index == 4 then
        -- AdjustRange *
        self.adjustRange = val1 / 100.0
    elseif index == 5 then
        -- AdjustSize
        self.adjustSize = val1 / 100.0
    elseif index == 6 then
        -- AdjustSoft *
        self.adjustSoft = val1 / 100.0
    end
end

function ClearPictureQuality:resize(width, height)

end

function ClearPictureQuality:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
end

function ClearPictureQuality:getXYScale(width, height)
    local size1 = math.min(width, height)
    local size2 = math.max(width, height) / 2.
    local baseSize = math.max(size1, size2)

    local xScale = baseSize / width
    local yScale = baseSize / height
    return xScale, yScale
end

function ClearPictureQuality:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    --- "Deep_Glow_30-effect0"
    --- draw1
    local fbo1 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo1:bind()
    self.program1:bind()
    self.program1:sendUniformf('u_threshold', (self.adjustRange * 0.83 + 0.5) * 0.75)
    self.program1:sendUniformf('u_thresholdSmooth', 0.1 * (self.adjustSoft * 3.0))
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- "Deep_Glow_30-effect0"
    --- draw4
    local fbo2 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.5, self.currentHeight * 0.5)
    fbo2:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 0.0)
    self.program2:sendUniformf('u_Strength', 3.109)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.5, self.currentHeight * 0.5)
    self.program2:sendUniformf('u_DownSample', 1.0)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw5
    local fbo3 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.5, self.currentHeight * 0.5)
    fbo3:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 90.0)
    self.program2:sendUniformf('u_Strength', 3.109)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.5, self.currentHeight * 0.5)
    self.program2:sendUniformf('u_DownSample', 1.0)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw6
    fbo2:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 0.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.5, self.currentHeight * 0.5)
    self.program2:sendUniformf('u_DownSample', 199.0 / 128.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw7
    local fbo5 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.5, self.currentHeight * 0.5)
    fbo5:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 90.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.5, self.currentHeight * 0.5)
    self.program2:sendUniformf('u_DownSample', 199.0 / 128.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw8
    local fbo6 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.25, self.currentHeight * 0.25)
    fbo6:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 0.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 64.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo5:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw9
    local fbo7 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.25, self.currentHeight * 0.25)
    fbo7:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 90.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 64.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo6:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw10
    fbo6:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 0.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 32.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo7:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw11
    local fbo9 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.25, self.currentHeight * 0.25)
    fbo9:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 90.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 32.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo6:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw12
    fbo6:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 0.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 16.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo9:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw13
    local fbo11 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.25, self.currentHeight * 0.25)
    fbo11:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 90.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 16.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo6:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw14
    fbo6:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 0.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 8.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo11:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw15
    local fbo13 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.25, self.currentHeight * 0.25)
    fbo13:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 90.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 8.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo6:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw16
    fbo6:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 0.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 4.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo13:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw17
    local fbo15 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.25, self.currentHeight * 0.25)
    fbo15:bind()
    self.program2:bind()
    self.program2:sendUniformf('u_Angle', 90.0)
    self.program2:sendUniformf('u_Strength', 4.0)
    self.program2:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program2:sendUniformf('u_DownSample', 199.0 / 4.0 * 2.0 * self.adjustSize)
    self.program2:sendUniformf('u_gamma', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo6:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw18
    local fbo16 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo16:bind()
    self.program3:bind()
    self.program3:sendUniformf('u_GlowIntensity', self.adjustLuminance * 2.0 * 0.7)
    self.program3:sendUniformf('u_gamma', 1.0)
    self.program3:sendUniformi('u_blendType', 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glActiveTexture(GL_TEXTURE2)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glActiveTexture(GL_TEXTURE3)
    glBindTexture(GL_TEXTURE_2D, fbo5:texId())
    glActiveTexture(GL_TEXTURE4)
    glBindTexture(GL_TEXTURE_2D, fbo7:texId())
    glActiveTexture(GL_TEXTURE5)
    glBindTexture(GL_TEXTURE_2D, fbo9:texId())
    glActiveTexture(GL_TEXTURE6)
    glBindTexture(GL_TEXTURE_2D, fbo11:texId())
    glActiveTexture(GL_TEXTURE7)
    glBindTexture(GL_TEXTURE_2D, fbo13:texId())
    glActiveTexture(GL_TEXTURE8)
    glBindTexture(GL_TEXTURE_2D, fbo15:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw19
    fbo1:bind()
    -- glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    -- glViewport(0, 0, self.currentWidth, self.currentHeight)
    self.program4:bind()
    self.program4:sendUniformi('u_BlendMode', 0)
    self.program4:sendUniformi('u_NeedBlend', 1)
    self.program4:sendUniformi('u_layerType', 1)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo16:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local xScale, yScale = self:getXYScale(self.currentWidth, self.currentHeight)
    local sigmaX = 7.5 * self.adjustBlur * 2.0 * xScale / 1000.0 / 2.5
    local sigmaY = 7.5 * self.adjustBlur * 2.0 * yScale / 1000.0 / 2.5
    --- draw22
    fbo16:bind()
    self.program5:bind()
    self.program5:sendUniformf('u_sampleX', 7.5 * self.adjustBlur)
    self.program5:sendUniformf('u_sigmaX', sigmaX)
    self.program5:sendUniformf('u_stepX', 2.0 * xScale / 1000.0)
    self.program5:sendUniformf('u_sigmaColor', 0.04)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw23
    local fbo19 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo19:bind()
    self.program6:bind()
    self.program6:sendUniformf('u_sampleY', 7.5 * self.adjustBlur)
    self.program6:sendUniformf('u_sigmaY', sigmaY)
    self.program6:sendUniformf('u_stepY', 2.0 * yScale / 1000.0)
    self.program6:sendUniformf('u_sigmaColor', 0.04)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo16:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local sampleX = 0.34 * self.adjustSharpen * 30.0
    local sampleY = 0.34 * self.adjustSharpen * 30.0
    sigmaX = sampleX * xScale / 1000.0 / 2.5
    sigmaY = sampleY * yScale / 1000.0 / 2.5
    --- draw24
    fbo16:bind()
    self.program7:bind()
    self.program7:sendUniformf('u_sampleX', sampleX)
    self.program7:sendUniformf('u_sigmaX', sigmaX)
    self.program7:sendUniformf('u_dx', xScale / 1000.0)
    self.program7:sendUniformi('u_borderType', 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo19:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glViewport(0, 0, self.currentWidth, self.currentHeight)
    self.program8:bind()
    self.program8:sendUniformf('u_sampleY', sampleY)
    self.program8:sendUniformf('u_sigmaY', sigmaY)
    self.program8:sendUniformf('u_dy', yScale / 1000.0)
    self.program8:sendUniformi('u_borderType', 0)
    self.program8:sendUniformf('u_strength', self.adjustSharpen * 1.5)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo16:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    AESP:recycleCachedFrameBuffer(fbo1)
    AESP:recycleCachedFrameBuffer(fbo2)
    AESP:recycleCachedFrameBuffer(fbo3)
    AESP:recycleCachedFrameBuffer(fbo5)
    AESP:recycleCachedFrameBuffer(fbo6)
    AESP:recycleCachedFrameBuffer(fbo7)
    AESP:recycleCachedFrameBuffer(fbo9)
    AESP:recycleCachedFrameBuffer(fbo11)
    AESP:recycleCachedFrameBuffer(fbo13)
    AESP:recycleCachedFrameBuffer(fbo15)
    AESP:recycleCachedFrameBuffer(fbo16)
    AESP:recycleCachedFrameBuffer(fbo19)
end

function ClearPictureQuality:onDestroy()
    glDeleteBuffers(1, {self.vertexBuffer})
end
    