
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

void main() {
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
uniform int channel;

void main() {
    vec4 c = texture2D(inputImageTexture, textureCoord);
    float a = c.a;
    c = c / a;
    c.a = a - 0.01;
    c = clamp(c, 0.0, 1.0);
    if (channel == 1) {
        c = vec4(c.r, c.r, c.r, 1.0);
    } else if (channel == 2) {
        c = vec4(c.g, c.g, c.g, 1.0);
    } else if (channel == 3) {
        c = vec4(c.b, c.b, c.b, 1.0);
    } else if (channel == 4) {
        c = vec4(c.a, c.a, c.a, 1.0);
    }
    gl_FragColor = c;
}
]]

ExtractChannel = {}

function ExtractChannel:matchWithId(effectId)
    return 'KFM KSkr ExtractChannel' == effectId
end

function ExtractChannel.createWithId(effectId)
    if not ExtractChannel:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, ExtractChannel)
    o:init()
    return o;
end

function ExtractChannel:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ExtractChannel:valueType(index)
    if index == 1 then
        -- Channel
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function ExtractChannel:updateValue(index, val1, val2, val3)
    local program = self.drawer:getProgram()
    program:bind()
    if index == 1 then
        -- Channel
        -- val1 is a index(starts with 1, not 0) of [R | G | B | A]
        program:sendUniformi('channel', val1)
    end
end

function ExtractChannel:resize(width, height)

end

function ExtractChannel:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function ExtractChannel:onDestroy()
end
    