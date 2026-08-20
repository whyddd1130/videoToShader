
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

uniform vec2 pointOne;
uniform vec3 colorOne;
uniform vec2 pointTwo;
uniform vec3 colorTwo;
uniform vec2 pointThree;
uniform vec3 colorThree;
uniform vec2 pointFour;
uniform vec3 colorFour;

uniform float blend;
uniform float opacity;
uniform int blendMode;

uniform vec2 imageSize;

float random(vec2 seed)
{
    return fract(sin(dot(seed ,vec2(12.9898,78.233))) * 43758.5453);
}

vec3 RGB2HSL(vec3 src)
{
    float maxc = max(max(src.r, src.g), src.b);
    float minc = min(min(src.r, src.g), src.b);
    float L = (maxc + minc) / 2.0;
    if(maxc == minc)
        return vec3(0.0, 0.0, L);
    float H, S;

    if(L < 0.5)
        S = (maxc - minc) / (maxc + minc);
    else
        S = (maxc - minc) / (2.0 - maxc - minc);

    if(maxc == src.r)
        H = (src.g - src.b) / (maxc - minc);
    else if(maxc == src.g)
        H = 2.0 + (src.b - src.r) / (maxc - minc);
    else
        H = 4.0 + (src.r - src.g) / (maxc - minc);
    H *= 60.0;
    if(H < 0.0) H += 360.0;
    return vec3(H / 360.0, S, L); // H(0~1), S(0~1), L(0~1)
}

vec3 HSL2RGB(vec3 src) // H, S, L
{
    if(src.y <= 0.0)
        return vec3(src.z, src.z, src.z);
    float q = (src.z < 0.5) ? src.z * (1.0 + src.y) : (src.z + src.y - (src.y * src.z));
    float p = 2.0 * src.z - q;

    vec3 dst = vec3(src.x + 0.333, src.x, src.x - 0.333);

    if(dst.r < 0.0) dst.r += 1.0;
    else if(dst.r > 1.0) dst.r -= 1.0;

    if(dst.g < 0.0) dst.g += 1.0;
    else if(dst.g > 1.0) dst.g -= 1.0;

    if(dst.b < 0.0) dst.b += 1.0;
    else if(dst.b > 1.0) dst.b -= 1.0;

    if(dst.r < 1.0 / 6.0)
        dst.r = p + (q - p) * 6.0 * dst.r;
    else if(dst.r < 0.5)
        dst.r = q;
    else if(dst.r < 2.0 / 3.0)
        dst.r = p + (q - p) * ((2.0 / 3.0) - dst.r) * 6.0;
    else dst.r = p;

    if(dst.g < 1.0 / 6.0)
        dst.g = p + (q - p) * 6.0 * dst.g;
    else if(dst.g < 0.5)
        dst.g = q;
    else if(dst.g < 2.0 / 3.0)
        dst.g = p + (q - p) * ((2.0 / 3.0) - dst.g) * 6.0;
    else dst.g = p;

    if(dst.b < 1.0 / 6.0)
        dst.b = p + (q - p) * 6.0 * dst.b;
    else if(dst.b < 0.5)
        dst.b = q;
    else if(dst.b < 2.0 / 3.0)
        dst.b = p + (q - p) * ((2.0 / 3.0) - dst.b) * 6.0;
    else dst.b = p;

    return dst;
}

float getLumValue(vec3 src)
{
    return dot(src, vec3(0.299, 0.587, 0.114));
}

vec3 blendFunc(vec3 src1, vec3 src2, float alpha, int blendMode)
{
    vec3 color = src1;
    if (blendMode == 2) //正常-
    {
        color = mix(src1, src2, alpha);
    }
    else if (blendMode == 3) //相加-
    {
        color = src1 + src2;
    }
    else if (blendMode == 4) //相乘-
    {
        color = src1 * (1.0 - alpha) + src1 * src2;
    }
    else if (blendMode == 5) //滤色-
    {
        color = src1 + src2 - src1 * src2;
    }
    else if (blendMode == 6) //叠加-
    {
        float revAlpha = 1.0 - alpha;
        vec3 src3 = src2 * 2.0;
        color = mix((src1 - 1.0) * (alpha - src3) + src1, src1 * src3 + src1 * revAlpha, step(src1, vec3(0.5)));
    }
    else if (blendMode == 7) //柔光-
    {
        color = mix(src1, src1 * (alpha * src1 + (2.0 * src2 * (1.0 - src1))) + src1 * (1.0 - alpha), alpha);
    }
    else if (blendMode == 8) //强光-
    {
        vec3 src1x2 = src1 * src2 * 2.0;
        src2 = mix(src1x2, ((src1 * alpha + src2) * 2.0 - src1x2 - alpha), step(0.5 * alpha, src2));
        color = src1 * (1.0 - alpha) + src2;
    }
    else if (blendMode == 9) //颜色减淡-
    {
        src2 = clamp(src2, 0.0, alpha - 0.001);
        color = mix(src1, min(alpha * src1 / (alpha - src2), 1.0), alpha);
    }
    else if (blendMode == 10) //颜色加深-
    {
        color = mix(src1, 1.0 - min((1.0 - src1) / (src2 + 0.001), 1.0), alpha);
    }
    else if (blendMode == 11) //变暗-
    {
        color = src1 * (1.0 - alpha) + min(src1 * alpha, src2);
    }
    else if (blendMode == 12) //变亮-
    {
        color = src1 * (1.0 - alpha) + max(src1 * alpha, src2);
    }
    else if (blendMode == 13) //差值-
    {
        color = src1 * (1.0 - alpha) + abs(src1 * alpha - src2);
    }
    else if (blendMode == 14) //排除-
    {
        color = src1 * (1.0 - alpha) + (alpha * src1 + src2 - src1 * src2 * 2.0);
    }
    else if (blendMode == 15) //色相-
    {
        vec3 hsl1 = RGB2HSL(src1);
        vec3 hsl2 = RGB2HSL(src2);
        vec3 dst = HSL2RGB(vec3(hsl2.r, hsl1.gb));

        color =  mix(src1, dst, alpha);
    }
    else if (blendMode == 16) //饱和度-
    {
        vec3 hsl1 = RGB2HSL(src1);
        vec3 hsl2 = RGB2HSL(src2);
        vec3 dst = HSL2RGB(vec3(hsl1.r, hsl2.g, hsl1.b));

        color =  mix(src1, dst, alpha);
    }
    else if (blendMode == 17) //颜色-
    {
        color = src1 * (1.0 - alpha) + getLumValue(src1 * alpha) - getLumValue(src2) + src2;
    }
    else if (blendMode == 18) //发光度-
    {
        color = mix(src1, getLumValue(src2) - getLumValue(src1) + src1, alpha);
    }
    return color;
}

void main() 
{
    vec4 color = texture2D(inputImageTexture, textureCoord);

    vec2 p[4];
    p[0] = pointOne / imageSize;
    p[1] = pointTwo / imageSize; 
    p[2] = pointThree / imageSize;
    p[3] = pointFour / imageSize;

    vec3 c[4];
    c[0] = colorOne;
    c[1] = colorTwo;
    c[2] = colorThree;
    c[3] = colorFour;

    vec4 gradientColor = vec4(0.0, 0.0, 0.0, 1.0);
    float valence = 0.0;

    for (int i = 0; i < 4; i++) 
    {
        float distance = length(textureCoord - p[i]);
        float w = 1.0 / pow(exp(distance), blend);
        gradientColor.rgb += w * c[i];
        valence += w;
    }
    gradientColor.rgb /= valence;

    //渐变颜色与原图混合
   if (blendMode == 1)
   {
       color = gradientColor * opacity;
   }
   else
   {
       color.rgb = blendFunc(color.rgb, gradientColor.rgb * opacity, color.a * opacity, blendMode);  
   }
    
    gl_FragColor = color;
}
]]

FourColorGradient = {}

function FourColorGradient:matchWithId(effectId)
    return 'KFM KSkr FourColorGradient' == effectId
end

function FourColorGradient.createWithId(effectId)
    if not FourColorGradient:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {},
        width = 720,
        height = 1280
    }
    o = newObject(o, FourColorGradient)
    o:init()
    return o;
end

function FourColorGradient:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.program = self.drawer:getProgram()
end

function FourColorGradient:valueType(index)
    if index == 1 then
        -- PointOne
        return FM.AEValueType_TwoD
    elseif index == 2 then
        -- ColorOne
        return FM.AEValueType_ThreeD
    elseif index == 3 then
        -- PointTwo
        return FM.AEValueType_TwoD
    elseif index == 4 then
        -- ColorTwo
        return FM.AEValueType_ThreeD
    elseif index == 5 then
        -- PointThree
        return FM.AEValueType_TwoD
    elseif index == 6 then
        -- ColorThree
        return FM.AEValueType_ThreeD
    elseif index == 7 then
        -- PointFour
        return FM.AEValueType_TwoD
    elseif index == 8 then
        -- ColorFour
        return FM.AEValueType_ThreeD
    elseif index == 9 then
        -- Blend
        return FM.AEValueType_OneDFloat
    elseif index == 10 then
        -- Opacity
        return FM.AEValueType_OneDFloat
    elseif index == 11 then
        -- Opacity
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function FourColorGradient:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        -- PointOne
        self.program:sendUniformf('pointOne', val1 , val2)
    elseif index == 2 then
        -- ColorOne
        self.program:sendUniformf('colorOne', val1, val2, val3)
    elseif index == 3 then
        -- PointTwo
        self.program:sendUniformf('pointTwo', val1, val2)
    elseif index == 4 then
        -- ColorTwo
        self.program:sendUniformf('colorTwo', val1, val2, val3)
    elseif index == 5 then
        -- PointThree
        self.program:sendUniformf('pointThree', val1, val2)
    elseif index == 6 then
        -- ColorThree
        self.program:sendUniformf('colorThree', val1, val2, val3)
    elseif index == 7 then
        -- PointFour
        self.program:sendUniformf('pointFour', val1, val2)
    elseif index == 8 then
        -- ColorFour
        self.program:sendUniformf('colorFour', val1, val2, val3)
    elseif index == 9 then
        -- Blend
        self.program:sendUniformf('blend', val1 * 0.01)
    elseif index == 10 then
        -- Opacity
        self.program:sendUniformf('opacity', val1 * 0.01)
    elseif index == 11 then
        self.program:sendUniformi('blendMode', val1)
    end

end

function FourColorGradient:resize(width, height)
    self.width = width
    self.height = height
    self.program:sendUniformf('imageSize', width, height)

end

function FourColorGradient:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function FourColorGradient:onDestroy()
end
    