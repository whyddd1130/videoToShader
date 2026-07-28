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
#endif

attribute vec2 position;
varying vec2 textureCoord;

void main()
{
    textureCoord = position*.5+.5;
    gl_Position = vec4(position, 0.,1.);
}
]]

---@language GLSL
local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

uniform sampler2D inputImageTexture;
varying vec2 textureCoord;
uniform float scaleSize;
//1上 2下 3左 4右
uniform float scaleDirection;
uniform float exponential;

void main() {
    float a = scaleDirection > 2. ?
    (scaleDirection > 3. ? textureCoord.x : 1.-textureCoord.x):
    (scaleDirection > 1. ? textureCoord.y : 1.-textureCoord.y);

    vec2 center = scaleDirection > 2. ?
    vec2(4.-scaleDirection, 0.5) :
    vec2(0.5,2.-scaleDirection);

    vec2 coordinate = textureCoord-center;
    float size = 1. + (scaleSize-1.) * pow(exponential, a*3.0-1.5);
    coordinate /= scaleDirection > 2. ? vec2(size,1.) : vec2(1.,size);
    gl_FragColor = texture2D(inputImageTexture, coordinate+center);
}
]]

EdgeStretch = {}

function EdgeStretch:matchWithId(effectId)
    return 'KFM KSkr EdgeStretch' == effectId
end

function EdgeStretch.createWithId(effectId)
    if not EdgeStretch:matchWithId(effectId) then
        return nil
    end
    local o = {
        program = {},
        vertexBuffer = 0
    }
    o = newObject(o, EdgeStretch)
    o:init()
    return o
end

function EdgeStretch:init()
    local buffer = {}
    glGenBuffers(1, buffer)
    self.vertexBuffer = buffer[1]

    local vertexBufferData = CGE.FloatBuffer:alloc(8)
    vertexBufferData:put(8, { -1, -1, 1, -1, -1, 1, 1, 1}, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, 8, vertexBufferData, GL_STATIC_DRAW)

    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation("position", 0)
    self.program:initWithShaderStrings(vs, fs)
    self.program:bind()
    self.program:sendUniformf('scaleSize', 1)
    self.program:sendUniformf('scaleDirection', 1)
    self.program:sendUniformf('exponential', 2)
end

function EdgeStretch:onDestroy()
    glDeleteBuffers(1, { self.vertexBuffer })
end

function EdgeStretch:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        return FM.AEValueType_OneDFloat
    elseif index == 3 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function EdgeStretch:updateValue(index, value1, value2, value3)
    self.program:bind();
    if index == 1 then
        self.program:sendUniformf("scaleSize", value1)
    elseif index == 2 then
        self.program:sendUniformf("scaleDirection", value1);
    elseif index == 3 then
        self.program:sendUniformf("exponential", value1);
    end
end

function EdgeStretch:updateTimeAndFrame(time, frame)
    --self.program:bind()
    --self.program:sendUniformf('scaleSize', 1+time)
end

function EdgeStretch:resize(width, height)
end

function EdgeStretch:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)

    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)

    self.program:bind();
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end
