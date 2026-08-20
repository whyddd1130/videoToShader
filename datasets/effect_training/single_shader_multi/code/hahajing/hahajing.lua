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
varying vec2 uv0;
void main()
{
    gl_Position = vec4(position, 0.0, 1.0);
    uv0 = position * 0.5 + 0.5;
}
]]

---@language GLSL
local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform float type;
uniform float maxOffsetX;
varying vec2 uv0;
uniform float inputHeight;
uniform float inputWidth;
uniform float offsetY;
uniform float offsetX;
uniform int needJoint;
uniform sampler2D inputImageTexture;

float calScale(float x) {
    float x0 = mix(3.0, 0.333333333, offsetY);
    float s =  3.0 / (type >= 0.5 ? mix(3.0, x0, x) : mix(x0, 3.0, x));
    return mix(1.0, s, offsetY);
}

vec2 changeUV(vec2 uv) {
    float scale =  calScale(uv.x);
    float y = uv.y * 2.0 - 1.0;
    y /= scale;
    y = 0.5 * (y + 1.0);

    float x = uv.x - offsetY * maxOffsetX;
    return vec2(x, y);
}

void main() {
    float ratio = inputWidth / inputHeight;
    vec2 uv = ( vec4((uv0.x * 2.0 - 1.0) * ratio, uv0.y * 2.0 - 1.0, 0.0, 1.0)).xy;
    uv.x += offsetX;

    uv.x = (uv.x / ratio + 1.0) / 2.0;
    uv.y = (uv.y + 1.0) / 2.0;
    uv = changeUV(uv);

    if(uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
    {
        if(needJoint == 1)
        {
            if(uv.x < 0.0) uv.x = -uv.x;
            if(uv.x > 1.0) uv.x = 2.0 - uv.x;
            if(uv.y < 0.0) uv.y = -uv.y;
            if(uv.y > 1.0) uv.y = 2.0 - uv.y;
            gl_FragColor = texture2D(inputImageTexture, uv) * step(uv.x, 2.0) * step(uv.y, 2.0) * step(-1.0, uv.x) * step(-1.0, uv.y);
        }
        else
        {
            gl_FragColor = vec4(0.0,0.0,0.0,0.0);
        }
    }
    else
    {
        gl_FragColor = texture2D(inputImageTexture, uv) * step(uv.x, 2.0) * step(uv.y, 2.0) * step(-1.0, uv.x) * step(-1.0, uv.y);
    }
}

]]

Hahajing = {}

function Hahajing:matchWithId(effectId)
    return 'KFM KSkr Hahajing' == effectId
end

function Hahajing.createWithId(effectId)
    if not Hahajing:matchWithId(effectId) then
        return nil
    end
    local o = {
        program = {},
        vertexBuffer = 0
    }
    o = newObject(o, Hahajing)
    o:init()
    return o
end

function Hahajing:init()
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

    self.program:sendUniformf("offsetY", 0)
    self.program:sendUniformf("offsetX", 0)
    self.program:sendUniformf("maxOffsetX", 1/9)
    self.program:sendUniformf("type", 1)
    self.program:sendUniformi("needJoint", 1)
end

function Hahajing:onDestroy()
    glDeleteBuffers(1, { self.vertexBuffer })
end

function Hahajing:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function Hahajing:updateValue(index, value1, value2, value3)
    self.program:bind();
    if index == 1 then
        if value1 < 0 then
            self.program:sendUniformf("type", 0)
            self.program:sendUniformf("maxOffsetX", -1/9)
            self.program:sendUniformf('offsetY', -value1)
            self.program:sendUniformf("offsetX", 0);
        else
            self.program:sendUniformf("type", 1)
            self.program:sendUniformf("maxOffsetX", 1/9)
            self.program:sendUniformf("offsetX", 0);
            self.program:sendUniformf('offsetY', value1)
        end
    elseif index == 2 then
        self.program:sendUniformi("needJoint", value1)
    end
end

function Hahajing:resize(width, height)
    self.program:bind();
    self.program:sendUniformf("inputWidth", width);
    self.program:sendUniformf("inputHeight", height);
end

function Hahajing:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)

    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)

    self.program:bind();
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end