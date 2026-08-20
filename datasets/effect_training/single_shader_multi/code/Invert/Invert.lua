
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
uniform int uChannel;
uniform float uIntensity;

const float pi = 3.1415927;

vec2 getUV() {
    return textureCoord;
}

vec4 getColor(vec2 uv) {
    return texture2D(inputImageTexture, uv);
}

vec3 rgb2yiq(vec3 src) {
    return src * mat3(0.299, 0.587, 0.114, 0.595716, -0.274453, -0.321263, 0.211456, -0.522591, 0.31135);
}

vec3 yiq2rgb(vec3 src) {
    return src * mat3(1.0, 0.9563, 0.6210, 1.0, -0.2721, -0.6474, 1.0, -1.1070, 1.7046);
}

vec3 RGB2HSL(vec3 src) {
    float maxc = max(max(src.r, src.g), src.b);
    float minc = min(min(src.r, src.g), src.b);
    float L = (maxc + minc) / 2.0;
    if (maxc == minc)
        return vec3(0.0, 0.0, L);
    float H, S;
    float temp1 = maxc - minc;
    S = mix(temp1 / (2.0 - maxc - minc), temp1 / (maxc + minc), step(L, 0.5));
    vec3 comp;
    comp.xy = vec2(equal(src.xy, vec2(maxc)));
    float comp_neg = 1.0 - comp.x;
    comp.y *= comp_neg;
    comp.z = (1.0 - comp.y) * comp_neg;

    float dif = maxc - minc;
    vec3 result = comp * vec3((src.g - src.b) / dif, 2.0 + (src.b - src.r) / dif, 4.0 + (src.r - src.g) / dif);

    H = result.x + result.y + result.z;

    H *= 60.0;
    //if(H < 0.0) H += 360.0;
    H += step(H, 0.0) * 360.0;
    return vec3(H / 360.0, S, L); // H(0~1), S(0~1), L(0~1)
}

vec3 HSL2RGB(vec3 src) // H, S, L
{
    float q = (src.z < 0.5) ? src.z * (1.0 + src.y) : (src.z + src.y - (src.y * src.z));
    float p = 2.0 * src.z - q;

    vec3 dst = vec3(src.x + 0.333, src.x, src.x - 0.333);
    dst = fract(dst);
    vec3 weight = step(dst, vec3(1.0 / 6.0));
    vec3 weight_neg = 1.0 - weight;

    vec3 weight2 = weight_neg * step(dst, vec3(0.5));
    vec3 weight2_neg = weight_neg * (1.0 - weight2);

    vec3 weight3 = weight2_neg * step(dst, vec3(2.0 / 3.0));
    vec3 weight4 = (1.0 - weight3) * weight2_neg;

    float q_p = q - p;

    dst = mix(dst, p + q_p * 6.0 * dst, weight);
    dst = mix(dst, vec3(q), weight2);
    dst = mix(dst, p + q_p * ((2.0 / 3.0) - dst) * 6.0, weight3);
    dst = mix(dst, vec3(p), weight4);

    return dst;
}

void main() {
    vec2 uv = getUV(); 
    vec4 rawColor = getColor(uv);
    vec3 color = rawColor.rgb;
    if (uChannel == 1) { // RGB
        color = 1.0 - color;
    } else if (uChannel == 2) { // R
        color.r = 1.0 - color.r;
    } else if (uChannel == 3) { // G
        color.g = 1.0 - color.g;
    } else if (uChannel == 4) { // B
        color.b = 1.0 - color.b;
    } else if (uChannel == 5) { // 色相
        vec3 yiq = rgb2yiq(color);
        float hue = atan(yiq.z, yiq.y);
        float chroma = length(yiq.yz);
        hue = pi - hue;
        yiq.yz = vec2(cos(hue), sin(hue)) * chroma;
        color = yiq2rgb(yiq);
    } else if (uChannel == 6) { // 亮度
        color = 1.0 - color;
        vec3 hsl = RGB2HSL(color);
        hsl.x = hsl.x + 0.5;
        color = HSL2RGB(hsl);
    } else if (uChannel == 7) { // 饱和度
        vec3 hsl = RGB2HSL(color);
        hsl.y = hsl.y + 0.5;
        color = HSL2RGB(hsl);
    }
    color = mix(color, rawColor.rgb, uIntensity);
    
    gl_FragColor = vec4(color, rawColor.a);
}
]]

Invert = {}

function Invert:matchWithId(effectId)
    return 'KFM KSkr Invert' == effectId
end

function Invert.createWithId(effectId)
    if not Invert:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, Invert)
    o:init()
    return o;
end

function Invert:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function Invert:valueType(index)
    if index == 1 then
        --Channel
        return FM.AEValueType_OneDInt
    elseif index == 2 then
        --Blend With Original
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function Invert:updateValue(index, val1, val2, val3)
    local program = self.drawer:getProgram()
    program:bind()
    if index == 1 then
        --Channel
        -- value is a index with [RGB | Red | Green | Blue | Hue | Lightness | Saturation]
        program:sendUniformi("uChannel", val1)
    elseif index == 2 then
        --Blend With Original
        program:sendUniformf("uIntensity", val1)
    end
end

function Invert:resize(width, height)

end

function Invert:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function Invert:onDestroy()
end
    