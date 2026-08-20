
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

uniform float uTime;
uniform vec3 metalColor;
uniform float metalFlow;

const float offset = 0.003;

float Difference(float blend, float base) {
    return abs(blend - base);
}

void main() {
    vec4 color = texture2D(inputImageTexture, textureCoord);

    vec4 color1 = texture2D(inputImageTexture, textureCoord+vec2(offset, 0.0));
    color1 += texture2D(inputImageTexture, textureCoord+vec2(-offset, 0.0));
    color1 += texture2D(inputImageTexture, textureCoord+vec2(0.0, offset));
    color1 += texture2D(inputImageTexture, textureCoord+vec2(0.0, -offset));

    color1 = (color + color1 * 0.25) * 0.5;

    float bias = fract(uTime * metalFlow);

    float gray = 0.114 * color1.b + 0.587 * color1.g + 0.299 * color1.r;
    
    gray = fract(gray + bias);

    float inver = 1.0 - gray;
    float diff = Difference(inver, gray);

    inver = 1.0 - diff;
    diff = Difference(inver, diff);

    inver = 1.0 - diff;
    diff = Difference(inver, diff);

    vec3 dye = metalColor * diff;

    gl_FragColor = vec4(dye, 1.0);
}
]]

Metalman = {}

function Metalman:matchWithId(effectId)
    return 'KFM KSkr Metalman' == effectId
end

function Metalman.createWithId(effectId)
    if not Metalman:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, Metalman)
    o:init()
    return o;
end

function Metalman:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function Metalman:valueType(index)
    if index == 1 then
        -- MetalColor
        return FM.AEValueType_ThreeD
    elseif index == 2 then
        -- MetalFlow
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function Metalman:updateTimeAndFrame(time, frame)
    self.drawer:getProgram():bind()
    self.drawer:getProgram():sendUniformf("uTime", time)
end

function Metalman:updateValue(index, val1, val2, val3)
    local program = self.drawer:getProgram()
    program:bind()
    if index == 1 then
        -- MetalColor
        program:sendUniformf('metalColor', val1, val2, val3)
    elseif index == 2 then
        -- MetalFlow
        program:sendUniformf('metalFlow', val1)
    end

end

function Metalman:resize(width, height)

end

function Metalman:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function Metalman:onDestroy()
end
    