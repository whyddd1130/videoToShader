
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
glass_2_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 v_texCoord;
uniform sampler2D u_srcSampler;
uniform float u_degree;
uniform vec2 u_size;

void main()
{
    vec2 ratio = vec2(720.0, u_size.y / u_size.x * 720.0);
    vec2 testCoord = v_texCoord * (ratio * (2.0 - u_degree));

    vec2 glass_offset = cos(testCoord * 0.035) / sin(testCoord * 0.035) * 3.0; //  玻璃效果
    vec2 glass_coord = testCoord + glass_offset;
    
    vec2 ps = vec2(1.0) / (ratio * (2.0 - u_degree));
    vec2 uv = testCoord * ps;
    
    vec2 glass_uv = glass_coord * ps;
    
    gl_FragColor = texture2D(u_srcSampler, glass_uv);
}
]]

MosaicGlass2 = {}

function MosaicGlass2:matchWithId(effectId)
    return 'KFM KSkr MosaicGlass2' == effectId
end

function MosaicGlass2.createWithId(effectId)
    if not MosaicGlass2:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, MosaicGlass2)
    o:init()
    return o;
end

function MosaicGlass2:init()
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
                self.program:initWithShaderStrings(basic_vs, glass_2_fs)
                self.program:bind()
                self.program:sendUniformi("u_srcSampler", 0)
                self.program:sendUniformf("u_degree", 1.0)
                self.program:sendUniformf("u_size", self.currentWidth, self.currentHeight)
end

function MosaicGlass2:valueType(index)
    if index == 1 then
        -- intensity
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function MosaicGlass2:updateValue(index, val1, val2, val3)
        if index == 1 then
        -- intensity
        self.program:bind()
        self.program:sendUniformf("u_degree", val1)
    end

end

function MosaicGlass2:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
    self.program:bind()
    self.program:sendUniformf("u_size", width, height)
end

function MosaicGlass2:resize(width, height)

end

function MosaicGlass2:render(outFBO, inputTex)
        local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])
    
            glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
        glViewport(0, 0, self.currentWidth, self.currentHeight)
        self.program:bind()
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, inputTex)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end

function MosaicGlass2:onDestroy()
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
    
