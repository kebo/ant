@echo off

set wdir=..\..\..\..\..
set shaderinc=%wdir%\pkg\ant.resources\shaders

set windowsdir=bin\windows
set windowvkdir=%windowsdir%\vulkan
set windowd3d11dir=%windowsdir%\direct3d11
mkdir %windowvkdir%
echo build windows d3d11 shader in %windowvkdir%...
%wdir%\bin\msvc\Debug\shaderc.exe --platform windows --type fragment -p s_5_0 -f mesh\fs_mesh.sc -o %windowd3d11dir%\fs_mesh.bin --depends -i %shaderinc% --debug
%wdir%\bin\msvc\Debug\shaderc.exe --platform windows --type vertex -p s_5_0 -f mesh\vs_mesh.sc -o %windowd3d11dir%\vs_mesh.bin --depends -i %shaderinc% --debug

%wdir%\bin\msvc\Debug\shaderc.exe --platform windows --type fragment -p s_5_0 -f fullquad\fs_quad.sc -o %windowd3d11dir%\fs_quad.bin --depends -i %shaderinc% --debug
%wdir%\bin\msvc\Debug\shaderc.exe --platform windows --type vertex -p s_5_0 -f fullquad\vs_quad.sc -o %windowd3d11dir%\vs_quad.bin --depends -i %shaderinc% --debug

mkdir %windowd3d11dir%
echo build windows vk shader in %windowd3d11dir% ...
%wdir%\bin\msvc\Debug\shaderc.exe --platform windows --type fragment -p spirv -f mesh\fs_mesh.sc -o %windowvkdir%\fs_mesh.bin --depends -i %shaderinc% --debug
%wdir%\bin\msvc\Debug\shaderc.exe --platform windows --type vertex -p spirv -f mesh\vs_mesh.sc -o %windowvkdir%\vs_mesh.bin --depends -i %shaderinc% --debug

%wdir%\bin\msvc\Debug\shaderc.exe --platform windows --type fragment -p spirv -f fullquad\fs_quad.sc -o %windowvkdir%\fs_quad.bin --depends -i %shaderinc% --debug
%wdir%\bin\msvc\Debug\shaderc.exe --platform windows --type vertex -p spirv -f fullquad\vs_quad.sc -o %windowvkdir%\vs_quad.bin --depends -i %shaderinc% --debug

set androiddir=bin\android
set androidvkdir=%androiddir%\vulkan
mkdir %androidvkdir%

echo build android vk shader in %androidvkdir% ...
%wdir%\bin\msvc\Debug\shaderc.exe --platform android --type fragment -p spirv -f mesh\fs_mesh.sc -o %androidvkdir%\fs_mesh.bin --depends -i %shaderinc% --debug
%wdir%\bin\msvc\Debug\shaderc.exe --platform android --type vertex -p spirv -f mesh\vs_mesh.sc -o %androidvkdir%\vs_mesh.bin --depends -i %shaderinc% --debug

%wdir%\bin\msvc\Debug\shaderc.exe --platform android --type fragment -p spirv -f fullquad\fs_quad.sc -o %androidvkdir%\fs_quad.bin --depends -i %shaderinc% --debug
%wdir%\bin\msvc\Debug\shaderc.exe --platform android --type vertex -p spirv -f fullquad\vs_quad.sc -o %androidvkdir%\vs_quad.bin --depends -i %shaderinc% --debug

echo finish...