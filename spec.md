# Spec
name: Desktop GUI Survey

This repo contains multiple implementations of a GUI for .png editing, enabling 
comparisons among different GUI tools. Each implementation should strive 
to have as many of the below features as possible.

## Features

### Feature: Runtime
The app should run on the MacOS, Windows, and Linux 
desktop operating systems. The build tools must produce a distributable file 
for each relevant combination of operating system and cpu arch:
    * windows-x86_64.exe
    * windows-arm64.exe
    * macos-x86_64.dmg
    * macos-arm64.dmg
    * linux-x86_64.deb
    * linux-arm64.deb
For MacOS, the distributable must also be signed / notarized.

### Feature: 2D Canvas Drawing
The app should provide a canvas to the user for drawing.
The user can draw in one of the following modes:
circle, rectangle, path

In circle mode, the user can draw circles. The first
click defines the circle center and the second click
defines the circle radius.

In rectangle mode, the user can draw rectangles.
The first click defines a rectangle corner and the
second click defines the opposite corner.

In path mode, the user can draw freehand curves.
The first mousedown presses down the "pen" and the
next mouseup raises the "pen". When the "pen" is down,
the area underneath the pen is colored. The pen color
and pen radius can be changed in the user settings.

### Feature: Filesystem Integration
The app should enable the user to save and 
load .png files from the filesystem.


### Feature: Hot Swapping (Live Preview)
This is a feature for developers, not end users. 

The app should have a hot swapping solution, which 
allows developers to see changes to source code immediately.
Seeing source code changes immediately greatly 
speeds up debugging and testing of the app.

The hot swapping must be *genuine hot reload*: edited source code is 
patched into the already-running process, and the app keeps running 
with its current state preserved. A watch loop that rebuilds and then 
restarts the app on every save does NOT satisfy this feature — 
restarting drops the app's state and is not hot swapping.

### Feature: Forms / Text Editing
The app should have a form with fields and text editing that 
allow users to read and write text-based metadata associated 
with the .png file. This metadata should be stored in the .png 
file as a 'tEXt' metadata chunk.
