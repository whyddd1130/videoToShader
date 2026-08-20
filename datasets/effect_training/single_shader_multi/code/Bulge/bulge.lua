
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
varying vec2 textureCoordinate;

void main()
{
    textureCoordinate = position * 0.5 + 0.5;
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

varying vec2 textureCoordinate;
    uniform sampler2D inputImageTexture;

    uniform vec2 imageSize;
    uniform float horizontalRadius;
    uniform float verticalRadius;
    uniform vec2 bulgeCenter;
    uniform float bulgeHeight;
    uniform float taperRadius;
    uniform int pinning;

    vec2 distort(vec2 r, float alpha) {
        return r * -alpha * (1.0 - dot(r, r));
    }

//vec2 distort1(vec2 p)
//{
//    float d = length(p);
//    float z = sqrt(distortion + d * d * -distortion);
//    float r = atan(d, z) / 3.1415926535;
//    float phi = atan(p.y, p.x);
//    return vec2(r * cos(phi) * (1.0 / imageSize.x * imageSize.y) + 0.5, r * sin(phi) + 0.5);
//}

     void main()
     {
        if(horizontalRadius <= 0.0 || verticalRadius <= 0.0)
        {
            gl_FragColor = texture2D(inputImageTexture, textureCoordinate);
            return;
        }

         vec2 uv = textureCoordinate;         
         float bulgeRadiusX = verticalRadius / horizontalRadius;
         float bulgeRadiusY = verticalRadius / imageSize.y;
         float ratio = imageSize.x / imageSize.y;
         
         float offset = ratio * bulgeRadiusX * 0.5 - 0.5;
         uv.x *= ratio * bulgeRadiusX;
         uv.x -= offset;
         
         //float taperRadiusToUse = taperRadius / max(verticalRadius, horizontalRadius);
         float taperRadiusToUse = 0.0;
         
         vec2 ratioCenter = bulgeCenter / imageSize,
         distVec = uv - ratioCenter;
         
         float dist = distance(ratioCenter, uv),
         normDist = dist / bulgeRadiusY;
         
         if (normDist < 1.)
         {
             //  内 -> 外   0.0 - 1.0
             if (normDist > 1.0 - taperRadiusToUse)
             {
                 normDist = smoothstep(1.0 - taperRadiusToUse, 1.0, normDist) * taperRadiusToUse + (1.0 - taperRadiusToUse);
             }
             
             if (bulgeHeight > 0.0)
             {
                 float a = atan(distVec.y, distVec.x);
                 //float newRadius = pow(normDist, bulgeHeight) * dist;
                 //uv = newRadius * vec2(cos(a),sin(a)) + ratioCenter;
                 float z = sqrt(bulgeHeight - normDist * normDist * bulgeHeight);
                 float r = atan(normDist, z) / 3.1415926535;
                 uv = vec2( r * cos(a) + ratioCenter.x, r * sin(a) + ratioCenter.y);
             }
             else
             {
                 uv = uv + distort(distVec, bulgeHeight) * (1.0 - normDist);
             }
         }
         uv = vec2((uv.x + offset) * (1.0 / (ratio * bulgeRadiusX)), uv.y);
         
         gl_FragColor = texture2D(inputImageTexture, uv);
         
         if (pinning > 0)
         {
             gl_FragColor *= min(1.0, step(uv.x, 0.0) + step(1.0, uv.x) + step(uv.y, 0.0) + step(1.0, uv.y));
         }
     }
]]

Bulge = {}

function Bulge:matchWithId(effectId)
    return 'KFM KSkr Bulge' == effectId
end

function Bulge.createWithId(effectId)
    if not Bulge:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {},
        currentWidth = 0,
        currentHeight = 0
    }
    o = newObject(o, Bulge)
    o:init()
    return o;
end

function Bulge:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.program = self.drawer:getProgram()
end

function Bulge:valueType(index)
    if index == 1 then
        -- HorizontalRadius
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        -- VerticalRadius
        return FM.AEValueType_OneDFloat
    elseif index == 3 then
        -- Center
        return FM.AEValueType_TwoD
    elseif index == 4 then
        -- Height
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        -- TaperRadius
        return FM.AEValueType_OneDFloat
    elseif index == 6 then
        -- Pinning
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function Bulge:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        -- HorizontalRadius
        self.program:sendUniformf("horizontalRadius", val1)
    elseif index == 2 then
        -- VerticalRadius
        self.program:sendUniformf("verticalRadius", val1)
    elseif index == 3 then
        -- Center
        self.program:sendUniformf("bulgeCenter", val1, val2)
    elseif index == 4 then
        -- Height
        self.program:sendUniformf("bulgeHeight", val1)
    elseif index == 5 then
        -- TaperRadius
        self.program:sendUniformf("taperRadius", val1)
    elseif index == 6 then
        -- Pinning
        self.program:sendUniformi("pinning", val1)
    end

end

function Bulge:resize(width, height)
    if self.currentWidth ~= width or self.currentHeight ~= height then
        self.currentWidth = width
        self.currentHeight = height

        self.program:bind()
        self.program:sendUniformf("imageSize", width, height)
    end

end

function Bulge:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function Bulge:onDestroy()
end
    