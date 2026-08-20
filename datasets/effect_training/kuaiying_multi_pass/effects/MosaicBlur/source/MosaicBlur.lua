
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

---@language GLSL
basic_vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
varying vec2 v_texCoord;

void main()
{
    v_texCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

---@language GLSL
blur_vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
uniform vec2 u_size;
uniform float u_degree;

varying vec2 blurCoordinates[13];

void main()
{
    gl_Position = vec4(position, 0.0, 1.0);
    
    int multiplier = 0;
    vec2 blurStep;
    float offset = u_degree * 0.005;
    vec2 singleStepOffset = vec2(offset, 0.0);
    
    for (int i = 0; i < 13; i++)
    {
        blurStep = float(-i) * singleStepOffset;
        blurCoordinates[i] = (position * 0.5 + 0.5) + blurStep;
    }
}
]]

---@language GLSL
blur_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D u_srcSampler;
varying vec2 blurCoordinates[13];

vec4 effectColor(vec2 loc) {
    return texture2D(u_srcSampler, loc);
}

void main()
{
    vec4 sum = vec4(0.0);
    sum += effectColor(blurCoordinates[0]) * 0.046118;
    sum += effectColor(blurCoordinates[1]) * 0.046118;
    sum += effectColor(blurCoordinates[2]) * 0.058552;
    sum += effectColor(blurCoordinates[3]) * 0.058552;
    sum += effectColor(blurCoordinates[4]) * 0.071181;
    sum += effectColor(blurCoordinates[5]) * 0.071181;
    sum += effectColor(blurCoordinates[6]) * 0.082860;
    sum += effectColor(blurCoordinates[7]) * 0.082860;
    sum += effectColor(blurCoordinates[8]) * 0.092356;
    sum += effectColor(blurCoordinates[9]) * 0.098568;
    sum += effectColor(blurCoordinates[10]) * 0.098568;
    sum += effectColor(blurCoordinates[11]) * 0.092356;
    sum += effectColor(blurCoordinates[12]) * 0.100731;

    gl_FragColor = sum;
}


]]

---@language GLSL
basic_gauss_2_v_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 v_texCoord;
uniform sampler2D u_srcSampler;
uniform float u_degree;

vec4 gauss()
{
    float u_blur = 0.002 + 0.006 * u_degree;
    vec4 sum = vec4(0.0);
    sum += texture2D(u_srcSampler, v_texCoord + vec2(0.0,-4.0*u_blur)) * 0.05;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(0.0,-3.0*u_blur)) * 0.09;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(0.0,-2.0*u_blur)) * 0.12;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(0.0,-1.0*u_blur)) * 0.15;
    sum += texture2D(u_srcSampler, v_texCoord) * 0.18;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(0.0,1.0*u_blur)) * 0.15;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(0.0,2.0*u_blur)) * 0.12;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(0.0,3.0*u_blur)) * 0.09;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(0.0,4.0*u_blur)) * 0.05;
    return sum;
}

void main()
{
    gl_FragColor = gauss();
}
]]

---@language GLSL
basic_gauss_2_h_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 v_texCoord;
uniform sampler2D u_srcSampler;
uniform float u_degree;

vec4 gauss()
{
    float u_blur = 0.002 + 0.006 * u_degree;
    vec4 sum = vec4(0.0);
    sum += texture2D(u_srcSampler, v_texCoord + vec2(-4.0*u_blur,0.0)) * 0.05;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(-3.0*u_blur,0.0)) * 0.09;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(-2.0*u_blur,0.0)) * 0.12;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(-1.0*u_blur,0.0)) * 0.15;
    sum += texture2D(u_srcSampler, v_texCoord) * 0.18;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(1.0*u_blur,0.0)) * 0.15;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(2.0*u_blur,0.0)) * 0.12;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(3.0*u_blur,0.0)) * 0.09;
    sum += texture2D(u_srcSampler, v_texCoord + vec2(4.0*u_blur,0.0)) * 0.05;
    return sum;
}

void main()
{
    gl_FragColor = gauss();
}
]]


MosaicBlur = {}

function MosaicBlur:matchWithId(effectId)
    return 'KFM KSkr MosaicBlur' == effectId
end

function MosaicBlur.createWithId(effectId)
    if not MosaicBlur:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, MosaicBlur)
    o:init()
    return o;
end

function MosaicBlur:init()
        self.type = 1
    self.frame = 0
    self.currentWidth = 720
    self.currentHeight = 1280
            self.mTex = 0
    self.mTex1 = 0
    self.mTex2 = 0
    self.mTex3 = 0
    self.currentTime = 0

    self.buffer = {}
    glGenBuffers(1,self.buffer)
    self.vbo = self.buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
    
                    self.program = CGE.ProgramObject()
                self.program:bindAttribLocation('position', 0)
                self.program:initWithShaderStrings(blur_vs, blur_fs)
                self.program:bind()
                self.program:sendUniformi("u_srcSampler", 0)
                self.program:sendUniformf("u_degree", 1.0)
                
                self.program2 = CGE.ProgramObject()
                self.program2:bindAttribLocation('position', 0)
                self.program2:initWithShaderStrings(basic_vs, basic_gauss_2_v_fs)
                self.program2:bind()
                self.program2:sendUniformi("u_srcSampler", 0)
                
                self.program3 = CGE.ProgramObject()
                self.program3:bindAttribLocation('position', 0)
                self.program3:initWithShaderStrings(basic_vs, basic_gauss_2_h_fs)
                self.program3:bind()
                self.program3:sendUniformi("u_srcSampler", 0)
end

function MosaicBlur:valueType(index)
    if index == 1 then
        -- intensity
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end


function MosaicBlur:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
    self.program:bind()
    self.program:sendUniformf("u_size", width, height)
end

function MosaicBlur:updateValue(index, val1, val2, val3)
       if index == 1 then
        -- intensity
        self.program:bind()
        self.program:sendUniformf("u_degree", val1)
        
                    self.program2:bind()
            self.program2:sendUniformf("u_degree", val1)
            self.program3:bind()
            self.program3:sendUniformf("u_degree", val1)
    end

end

function MosaicBlur:resize(width, height)

end

function MosaicBlur:render(outFBO, inputTex)
        local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])
    
            local fbo = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
        fbo:bind()
        self.program2:bind()
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, inputTex)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

        local fbo2 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
        fbo2:bind()
        self.program3:bind()
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, fbo:texId())
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
        
        glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
        glViewport(0, 0, self.currentWidth, self.currentHeight)
        self.program:bind()
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, fbo2:texId())
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
        
        AESP:recycleCachedFrameBuffer(fbo)
        AESP:recycleCachedFrameBuffer(fbo2)
end

    
function MosaicBlur:onDestroy()
    if self.mTex ~= 0 then
        glDeleteTextures(1, {self.mTex})
    end
    if self.mTex1 ~= 0 then
        glDeleteTextures(1, {self.mTex1})
    end
    if self.mTex2 ~= 0 then
        glDeleteTextures(1, {self.mTex2})
    end
    if self.mTex3 ~= 0 then
        glDeleteTextures(1, {self.mTex3})
    end
    
    glDeleteBuffers(#self.buffer, self.buffer)
    
    if self.buffers then
        glDeleteBuffers(#self.buffers, self.buffers)
        self.buffers = nil
    end
end
    
