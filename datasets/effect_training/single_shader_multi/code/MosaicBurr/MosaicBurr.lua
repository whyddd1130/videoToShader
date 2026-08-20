
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
burr_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 v_texCoord;
uniform sampler2D u_srcSampler;
uniform float u_degree;
uniform vec2 u_size;

const float scanlines = 0.3;
const float fuzz = .005;
const float fuzzDensity = 999.;
const float chromatic = .005;
const float staticNoise = .9;
const float ghost = 0.2 * 0.0;
const float verticalMovement = 2.;
const float verticalMovementPercent = .2;
const float vignette = 1.1;
const float pi = 3.14159265359;

float hash(vec2 p)
{
    p  = 50.0*fract( p*0.3183099 + vec2(0.71,0.113));
    return -1.0+2.0*fract( p.x*p.y*(p.x+p.y) );
}

float noise(in vec2 p )
{
    vec2 i = floor( p );
    vec2 f = fract( p );
    vec2 u = f*f*(3.0-2.0*f);
    return mix( mix( hash( i + vec2(0.0,0.0) ),
                        hash( i + vec2(1.0,0.0) ), u.x),
                mix( hash( i + vec2(0.0,1.0) ),
                        hash( i + vec2(1.0,1.0) ), u.x), u.y);
}

vec4 glitch(float alpha)
{
    float iTime = 1.0;
        
    vec2 uv = v_texCoord;

    vec4 c = vec4(0.0);
    c += staticNoise * ((sin(iTime)+2.)*.3)*sin(.8-uv.y+sin(iTime*3.)*.1) *
        noise(vec2(uv.y*999. + iTime*999., (uv.x+999.)/(uv.y+.1)*19.)) * alpha;
    
    uv.x += fuzz*noise(vec2(uv.y*fuzzDensity, iTime*9.)) * u_degree * 10.0;
    
    // uv.y += mix(0., sin(iTime*.2)*5.0,
    //     step(noise(vec2(iTime*.5,0.))*.5+.5, verticalMovementPercent));
    // uv.y = fract(uv.y);

    uv.y += fuzz*noise(vec2(uv.x*fuzzDensity, iTime*9.)) * u_degree;

    float g = hash(vec2(uv.x+sin(iTime), uv.y));
    uv.x += mix(0., sin(iTime/5.0)*0.5, step(g, ghost - 1.));
    uv.y += mix(0., .2*sin(iTime/5.0)*0.5, step(g, ghost - 1.));

    c += vec4
    (
        texture2D(u_srcSampler, uv + vec2(-chromatic, 0)).r,
        texture2D(u_srcSampler, uv + vec2( 0        , 0)).g,
        texture2D(u_srcSampler, uv + vec2( chromatic, 0)).b,
        1.
    );
    
    uv = v_texCoord;
    
    c *= (1. + scanlines*sin(uv.y*u_size.y *pi/2.));
    
    float dx = vignette * abs(uv.x - .5);
    float dy = vignette * abs(uv.y - .5);
    c *= (1.0 - dx * dx - dy * dy);
    
    return c;
}

void main()
{
    gl_FragColor = glitch(texture2D(u_srcSampler, v_texCoord).a);
}
]]


MosaicBurr = {}

function MosaicBurr:matchWithId(effectId)
    return 'KFM KSkr MosaicBurr' == effectId
end

function MosaicBurr.createWithId(effectId)
    if not MosaicBurr:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, MosaicBurr)
    o:init()
    return o;
end

function MosaicBurr:init()
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
                self.program:initWithShaderStrings(basic_vs, burr_fs)
                self.program:bind()
                self.program:sendUniformi("u_srcSampler", 0)
                self.program:sendUniformf("u_degree", 1.0)
                self.program:sendUniformf("u_size", self.currentWidth, self.currentHeight)
end

function MosaicBurr:valueType(index)
    if index == 1 then
        -- intensity
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function MosaicBurr:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
    self.program:bind()
    self.program:sendUniformf("u_size", width, height)
end


function MosaicBurr:updateValue(index, val1, val2, val3)
        if index == 1 then
        -- intensity
        self.program:bind()
        self.program:sendUniformf("u_degree", val1)
    end

end

function MosaicBurr:resize(width, height)

end

function MosaicBurr:render(outFBO, inputTex)
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

function MosaicBurr:onDestroy()
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
    
