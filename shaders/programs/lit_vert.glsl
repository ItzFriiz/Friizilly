#version 460

//attributes
in vec3 vaPosition; // vertex position in model space
in vec2 vaUV0;  // 纹理坐标
in vec4 vaColor;    // 纹理坐标对应颜色
in ivec2 vaUV2; // 光源贴图坐标，范围[1, 256]
in vec4 at_tangent; // xyz = tangent vector, w = handedness
in vec3 mc_Entity;  // x = blockId

//uniforms
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat4 gbufferModelViewInverse;
uniform mat3 normalMatrix;  // convert normal from model to view space

uniform vec3 chunkOffset;   // 模型相对于世界坐标的偏移量
uniform vec3 cameraPosition;

out vec2 texCoord;
out vec3 foliageColor;
out vec2 lightMapCoords;
out vec3 viewSpacePosition;
out vec4 viewTangent;
out float blockId;

void main() {

    blockId = mc_Entity.x;
    viewTangent = vec4(normalize(normalMatrix * at_tangent.rgb), at_tangent.a); // 目标平面在view space中的切向量
    texCoord = vaUV0;
    foliageColor = vaColor.rgb;
    lightMapCoords = vaUV2 * (1.0 / 256.0) + (1.0 / 32.0);  // 归一化到浮点数[0,1]

    vec4 viewSpacePositionVec4 = modelViewMatrix * vec4(vaPosition + chunkOffset, 1);
    viewSpacePosition = viewSpacePositionVec4.xyz;
    
    gl_Position = projectionMatrix * viewSpacePositionVec4;
}