
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

uniform float hue;
uniform float lightness;
uniform float saturation;

vec3 HSL2RGB(vec3 src) // H, S, L
{
    if (src.y <= 0.0)
        return vec3(src.z, src.z, src.z);
    float q = (src.z < 0.5) ? src.z * (1.0 + src.y) : (src.z + src.y - (src.y * src.z));
    float p = 2.0 * src.z - q;

    vec3 dst = vec3(src.x + 0.333, src.x, src.x - 0.333);

    if (dst.r < 0.0)
        dst.r += 1.0;
    else if (dst.r > 1.0)
        dst.r -= 1.0;

    if (dst.g < 0.0)
        dst.g += 1.0;
    else if (dst.g > 1.0)
        dst.g -= 1.0;

    if (dst.b < 0.0)
        dst.b += 1.0;
    else if (dst.b > 1.0)
        dst.b -= 1.0;

    if (dst.r < 1.0 / 6.0)
        dst.r = p + (q - p) * 6.0 * dst.r;
    else if (dst.r < 0.5)
        dst.r = q;
    else if (dst.r < 2.0 / 3.0)
        dst.r = p + (q - p) * ((2.0 / 3.0) - dst.r) * 6.0;
    else
        dst.r = p;

    if (dst.g < 1.0 / 6.0)
        dst.g = p + (q - p) * 6.0 * dst.g;
    else if (dst.g < 0.5)
        dst.g = q;
    else if (dst.g < 2.0 / 3.0)
        dst.g = p + (q - p) * ((2.0 / 3.0) - dst.g) * 6.0;
    else
        dst.g = p;

    if (dst.b < 1.0 / 6.0)
        dst.b = p + (q - p) * 6.0 * dst.b;
    else if (dst.b < 0.5)
        dst.b = q;
    else if (dst.b < 2.0 / 3.0)
        dst.b = p + (q - p) * ((2.0 / 3.0) - dst.b) * 6.0;
    else
        dst.b = p;

    return dst;
}

vec3 RGB2HSL(vec3 src)
{
    float maxc = max(max(src.r, src.g), src.b);
    float minc = min(min(src.r, src.g), src.b);
    float L = (maxc + minc) / 2.0;
    if (maxc == minc)
        return vec3(0.0, 0.0, L);
    float H, S;

    if (L < 0.5)
        S = (maxc - minc) / (maxc + minc);
    else
        S = (maxc - minc) / (2.0 - maxc - minc);

    if (maxc == src.r)
        H = (src.g - src.b) / (maxc - minc);
    else if (maxc == src.g)
        H = 2.0 + (src.b - src.r) / (maxc - minc);
    else
        H = 4.0 + (src.r - src.g) / (maxc - minc);
    H *= 60.0;
    if (H < 0.0) H += 360.0;
    return vec3(H / 360.0, S, L); // H(0~1), S(0~1), L(0~1)
}

void main() 
{
    vec4 src = texture2D(inputImageTexture, textureCoord);
    float angle = hue / 180.0 * 3.14159265;
    float s = sin(angle);
    float c = cos(angle);

    vec3 weights = (vec3(2.0 * c, -sqrt(3.0) * s - c, sqrt(3.0) * s - c) + 1.0) / 3.0;
    float len = length(src.rgb);
    src.rgb = vec3(dot(src.rgb, weights.xyz), dot(src.rgb, weights.zxy), dot(src.rgb, weights.yzx));
    src.rgb = src.rgb + vec3(lightness / 100.0);

    vec3 hsl = RGB2HSL(src.rgb);
    hsl.y += saturation / 100.0;
    src.rgb = HSL2RGB(hsl);

    gl_FragColor = src * src.a;
}
]]

ColorBalanceHLS = {}

function ColorBalanceHLS:matchWithId(effectId)
    return 'KFM KSkr ColorBalanceHLS' == effectId
end

function ColorBalanceHLS.createWithId(effectId)
    if not ColorBalanceHLS:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {},
        hue = 0.0,
        lightness = 0.0,
        saturation = 0.0
    }
    o = newObject(o, ColorBalanceHLS)
    o:init()
    return o;
end

function ColorBalanceHLS:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.program = self.drawer:getProgram()
end

function ColorBalanceHLS:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- Hue
        self.hue = val1
    elseif index == 2 then
        -- Lightness
        self.lightness = val1
    elseif index == 3 then
        -- Saturation
        self.saturation = val1
    end
end

function ColorBalanceHLS:resize(width, height)

end

function ColorBalanceHLS:customResize(width, height)

end

function ColorBalanceHLS:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.program:bind()
    self.program:sendUniformf('hue', self.hue)
    self.program:sendUniformf('lightness', self.lightness)
    self.program:sendUniformf('saturation', self.saturation)
    self.drawer:drawTexture(inputTex)
end

function ColorBalanceHLS:onDestroy()
end
    