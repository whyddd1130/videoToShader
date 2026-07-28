
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

uniform vec2 screenSize;
uniform float radius;
uniform float blurSize;

vec3 getWeight(vec3 Col1,vec3 Col2,float T)
{
    return max(1.-abs(Col1-Col2)/(2.5*T),0.);
}
vec4 blur(sampler2D inputTexture,vec2 textureCoordinate, float blurRadius, float stepUV, vec2 screenSize,float T)
{
    vec2 unitUV = vec2(stepUV,stepUV)/screenSize;
    vec4 oriCol = texture2D(inputTexture,textureCoordinate);
    vec4 midCol;
    vec3 midweight;
    vec4 sumColor=vec4(0.);
    vec3 sumWeight=vec3(0.0);
    vec2 textureCoordinateA;
    vec2 textureCoordinateB;
    vec4 colorA;
    vec4 colorB;
    vec3 weightA;
    vec3 weightB;
    for(float j=-floor(blurRadius);j<=7.01;j+=1.0){
        if(j>blurRadius){
            break;
        }
        midCol=texture2D(inputTexture,textureCoordinate+vec2(j,0)*unitUV);
        midweight=getWeight(oriCol.rgb,midCol.rgb,T);
        sumColor.rgb+=midCol.rgb*midweight;
        sumWeight+=midweight;
        for(float i=1.;i<=7.01;i+=1.0)
        {
            if(i>blurRadius){
            break;
            }
            textureCoordinateA = textureCoordinate+vec2(j,i)*unitUV;
            textureCoordinateB = textureCoordinate+vec2(j,-i)*unitUV;
            colorA = texture2D(inputTexture,textureCoordinateA);
            colorB = texture2D(inputTexture,textureCoordinateB);
            weightA = getWeight(oriCol.rgb,colorA.rgb,T);
            weightB = getWeight(oriCol.rgb,colorB.rgb,T);
            sumColor.rgb += colorA.rgb*weightA;
            sumColor.rgb += colorB.rgb*weightB;
            sumWeight+= weightA+weightB;
        }
    }
    vec3 resultCol = clamp(sumColor.rgb/sumWeight,0.,1.);
    return vec4(resultCol,oriCol.a);
}

void main()
{
    vec4 col = blur(inputImageTexture, textureCoord, radius, 1.0, screenSize, blurSize/255.);
    gl_FragColor = vec4(col);
}
]]

SurfaceBlur = {}

function SurfaceBlur:matchWithId(effectId)
    return 'KFM KSkr SurfaceBlur' == effectId
end

function SurfaceBlur.createWithId(effectId)
    if not SurfaceBlur:matchWithId(effectId) then
        return nil
    end
    local o = {
        program = {},
        currentWidth = 0,
        currentHeight = 0,
        blurSize = 0,
        blurIntensity = 0
    }
    o = newObject(o, SurfaceBlur)
    o:init()
    return o;
end

function SurfaceBlur:init()
    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation('position', 0)
    self.program:initWithShaderStrings(vs, fs)
    self.program:bind()
    self.program:sendUniformi('inputImageTexture', 0)

    local buffer = {}
    glGenBuffers(1,buffer) 
    self.vertexBuffer = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
end

function SurfaceBlur:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- BlurSize
        self.blurSize = val1 / 100.0
    elseif index == 2 then
        -- BlurIntensity
        self.blurIntensity = val1 / 100.0
    end
end

function SurfaceBlur:resize(width, height)

end

function SurfaceBlur:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
end

function SurfaceBlur:remap(x, a, b)
    return x * (b - a) + a
end

function SurfaceBlur:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glViewport(0, 0, self.currentWidth, self.currentHeight)
    self.program:bind()
    self.program:sendUniformf('screenSize', self.currentWidth, self.currentHeight)
    self.program:sendUniformf('radius', self:remap(self.blurIntensity, 0.001, 8))
    self.program:sendUniformf('blurSize', self:remap(self.blurSize, 0.001, 25))
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end

function SurfaceBlur:onDestroy()
    glDeleteBuffers(1, {self.vertexBuffer})
end
    