-- MipmapBlur - 稳定单 Pass 模糊

local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

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
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

local main_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform vec2 texelSize;
uniform float blurRadius;
uniform float blendAmount;

void main()
{
    vec2 uv = textureCoord;
    vec2 stepOffset = texelSize * max(blurRadius, 0.0);

    vec4 center = texture2D(inputImageTexture, uv) * 0.227027;
    vec4 blur = center;
    blur += texture2D(inputImageTexture, uv + vec2(stepOffset.x * 1.384615, 0.0)) * 0.316216;
    blur += texture2D(inputImageTexture, uv - vec2(stepOffset.x * 1.384615, 0.0)) * 0.316216;
    blur += texture2D(inputImageTexture, uv + vec2(stepOffset.x * 3.230769, 0.0)) * 0.070270;
    blur += texture2D(inputImageTexture, uv - vec2(stepOffset.x * 3.230769, 0.0)) * 0.070270;
    blur += texture2D(inputImageTexture, uv + vec2(0.0, stepOffset.y * 1.384615)) * 0.316216;
    blur += texture2D(inputImageTexture, uv - vec2(0.0, stepOffset.y * 1.384615)) * 0.316216;
    blur += texture2D(inputImageTexture, uv + vec2(0.0, stepOffset.y * 3.230769)) * 0.070270;
    blur += texture2D(inputImageTexture, uv - vec2(0.0, stepOffset.y * 3.230769)) * 0.070270;

    gl_FragColor = mix(center, blur, clamp(blendAmount, 0.0, 1.0));
}
]]

MipmapBlur = {}

function MipmapBlur:matchWithId(effectId)
    if "KFM KSkr MipmapBlur" == effectId then return true end
    return false
end

function MipmapBlur.createWithId(effectId)
    if not MipmapBlur:matchWithId(effectId) then
        return nil
    end
    local o = {
        program = {},
        vbo = 0,
        blurRadius = 3.0,
        blendAmount = 1.0,
        texelWidth = 1.0 / 1080.0,
        texelHeight = 1.0 / 1080.0
    }
    o = newObject(o, MipmapBlur)
    o:init()
    return o
end

function MipmapBlur:init()
    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation('position', 0)
    self.program:initWithShaderStrings(vs, main_fs)
    self.program:bind()
    self.program:sendUniformi('inputImageTexture', 0)
    self.program:sendUniformf('texelSize', self.texelWidth, self.texelHeight)
    self.program:sendUniformf('blurRadius', self.blurRadius)
    self.program:sendUniformf('blendAmount', self.blendAmount)

    local buffer = {}
    glGenBuffers(1, buffer)
    self.vbo = buffer[1]
    local vertices = {-1,-1, 1,-1, -1,1, 1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function MipmapBlur:valueType(index)
    if index == 1 or index == 2 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function MipmapBlur:updateValue(index, val1, val2, val3)
    if index == 1 then
        self.blurRadius = math.max(0.0, val1)
    elseif index == 2 then
        self.blendAmount = math.max(0.0, math.min(1.0, val1 / 100.0))
    end
end

function MipmapBlur:resize(width, height)
    if width > 0 and height > 0 then
        self.texelWidth = 1.0 / width
        self.texelHeight = 1.0 / height
    end
end

function MipmapBlur:drawQuad()
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end

function MipmapBlur:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.program:bind()
    self.program:sendUniformf('texelSize', self.texelWidth, self.texelHeight)
    self.program:sendUniformf('blurRadius', self.blurRadius)
    self.program:sendUniformf('blendAmount', self.blendAmount)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    self:drawQuad()
end

function MipmapBlur:onDestroy()
    if self.vbo then
        glDeleteBuffers(1, {self.vbo})
    end
end
