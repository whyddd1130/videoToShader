
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

uniform float splashRate;
uniform int splashColorIndex;
uniform float frame;

void main() 
{
    vec4 resultColor = texture2D(inputImageTexture, textureCoord);

    vec4 splashColor = vec4(0.0, 0.0, 0.0, 1.0);
    if (splashColorIndex == 2)
    {
        splashColor = vec4(1.0);
    }
    if (splashColorIndex == 3)
    {
        splashColor = vec4(1.0, 1.0, 0.0, 1.0);
    }

    if (float(mod(floor(frame), floor(12.0 - splashRate))) > 0.1)
    {
        resultColor = splashColor;
    }

    gl_FragColor = resultColor;
}
]]

SplashScreen = {}

function SplashScreen:matchWithId(effectId)
    return 'KFM KSkr SplashScreen' == effectId
end

function SplashScreen.createWithId(effectId)
    if not SplashScreen:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {},
        splashRate = 0.0,
        splashColorIndex = 1
    }
    o = newObject(o, SplashScreen)
    o:init()
    return o;
end

function SplashScreen:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.program = self.drawer:getProgram()
end

function SplashScreen:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- SplashRate
        self.splashRate = val1
    elseif index == 2 then
        -- SplashColor
        -- val1 is a index(starts with 1, not 0) of [Black | White | Yellow]
        self.splashColorIndex = val1
    end

end

function SplashScreen:updateTimeAndFrame(time, frame)
    self.program:bind()
    self.program:sendUniformf("frame", frame)

    -- print('&&&&&&&&&&&&&' .. time)
    -- print('&&&&&&&&&&&&&**********' .. frame)
end

function SplashScreen:resize(width, height)

end

function SplashScreen:customResize(width, height)

end

function SplashScreen:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.program:bind()
    self.program:sendUniformf('splashRate', self.splashRate)
    self.program:sendUniformi('splashColorIndex', self.splashColorIndex)
    self.drawer:drawTexture(inputTex)
end

function SplashScreen:onDestroy()
end
    