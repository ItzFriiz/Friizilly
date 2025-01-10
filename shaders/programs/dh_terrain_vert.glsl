#version 460 compatibility

out vec4 blockColor;
out vec2 lightMapCoords;
out vec3 viewSpacePosition;

void main() {
    blockColor = gl_Color;
    lightMapCoords = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

    viewSpacePosition = (gl_ModelViewMatrix * gl_Vertex).xyz;

    gl_Position = ftransform();
}