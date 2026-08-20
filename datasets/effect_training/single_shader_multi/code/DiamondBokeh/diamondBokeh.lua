
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

uniform vec2 u_ScreenSize;
uniform float u_Size;
uniform float u_Angle;
uniform float u_Bright;
uniform float u_SizeScale;

vec4 dirBlur(sampler2D inputTexture, vec2 uv, vec2 dir)
{
    float sigma = 7.0;
    float weight = 1.0;
    vec4 resColor = texture2D(inputTexture, uv) * weight;
    float sumWeight = weight;
    vec4 maxColor = resColor;
    float curWeight = 1.0;
    float delay = 0.9;
    float delayWight = curWeight;
    for (int i = 1; i <= 16; ++i)
    {
        weight = 1.0;
        delayWight = delay * delayWight;
        vec2 tmpUV = uv + dir * float(i) * u_Size * u_SizeScale;
        vec4 a = texture2D(inputTexture, tmpUV) * weight;
        tmpUV = uv - dir * float(i) * u_Size * u_SizeScale;
        vec4 b = texture2D(inputTexture, tmpUV);
        resColor += a + b;
        vec4 c = max(a, b);
        maxColor = max(c, maxColor);

        sumWeight += 2.0 * weight;
    }
    resColor /= sumWeight;
    vec4 color = mix(resColor, maxColor, clamp(resColor * u_Bright, 0.0, 1.0));
    resColor.rgb = color.rgb;
    return resColor;
}

void main() 
{
    float theta = u_Angle * 3.1415926 / 180.0;
    vec2 rect = vec2(min(720.0, 720.0 * u_ScreenSize.x / u_ScreenSize.y), min(720.0, 720.0 * u_ScreenSize.y / u_ScreenSize.x));
    vec2 dir = vec2(cos(theta), sin(theta)) / rect;
    vec4 color = dirBlur(inputImageTexture, textureCoord, dir);
    gl_FragColor = color;
}
]]

DiamondBokeh = {}

function DiamondBokeh:matchWithId(effectId)
    return 'KFM KSkr DiamondBokeh' == effectId
end

function DiamondBokeh.createWithId(effectId)
    if not DiamondBokeh:matchWithId(effectId) then
        return nil
    end
    local o = {
        blurDrawer = {},
        blurProgram = {},
        progress = 0.01,
        speed = 0.33,
        flag = 0.33,
        spotSize = 0.6,
        spotIntensity = 0.7,
        currentWidth = 720,
        currentHeight = 1280
    }
    o = newObject(o, DiamondBokeh)
    o:init()
    return o;
end

function DiamondBokeh:init()
    self.blurDrawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.blurProgram = self.blurDrawer:getProgram()
end

function DiamondBokeh:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- spotSize
        self.spotSize = val1
    elseif index == 2 then
        -- spotIntensity
        self.spotIntensity = val1
    elseif index == 3 then
        -- speed
        self.speed = val1
    elseif index == 4 then
        -- progress
        self.progress = val1
    elseif index == 5 then
        -- reverseBokeh
        self.flag = val1
    end
end

function DiamondBokeh:resize(width, height)

end

function DiamondBokeh:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height

    self.blurProgram:bind()
    self.blurProgram:sendUniformf('u_ScreenSize', width, height)
end

function DiamondBokeh:step (edge0, edge1, value)
    return math.min(math.max(0, (value - edge0) / (edge1 - edge0)), 1)
end

function DiamondBokeh:mix (x, y, a)
    return x + (y - x) * a
end

function DiamondBokeh:remap(x, a, b)
    return x * (b - a) + a
end

function DiamondBokeh:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    if self.flag > 0.5 then
        self.progress = 1.0 - self.progress
    end

    local intensity = 0.0
    if self.speed < 1.0 / 100.0 then
        intensity = 1.0
    elseif self.speed < 1.0 / 3.0 then
        intensity = self:step(self:mix(2, 1, self:step(1.0 / 100.0, 1.0 / 3.0, self.speed)), 0, self.progress) 
    else
        intensity = self:step(self:mix(1, 0.5, self:step(1.0 / 3.0, 1.0, self.speed)), 0, self.progress)
    end

    local curFbo = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    curFbo:bind()
    self.blurProgram:bind()
    self.blurProgram:sendUniformf('u_Angle', 45.0)
    self.blurProgram:sendUniformf('u_SizeScale', intensity)
    self.blurProgram:sendUniformf('u_Size', self:remap(self.spotSize, 0, 1.0))
    self.blurProgram:sendUniformf('u_Bright', self:remap(self.spotIntensity, 1.0, 5.0))
    self.blurDrawer:drawTexture(inputTex)

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.blurProgram:bind()
    self.blurProgram:sendUniformf('u_Angle', 135.0)
    self.blurProgram:sendUniformf('u_SizeScale', intensity)
    self.blurProgram:sendUniformf('u_Size', self:remap(self.spotSize, 0, 1.0))
    self.blurProgram:sendUniformf('u_Bright', self:remap(self.spotIntensity, 1.0, 5.0))
    self.blurDrawer:drawTexture(curFbo:texId())

    AESP:recycleCachedFrameBuffer(curFbo)
end

function DiamondBokeh:onDestroy()
end
    