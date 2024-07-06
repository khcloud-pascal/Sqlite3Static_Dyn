
This folder contains all raw binary files needed for FPC static linking.

Mainly needed for SynSQLite3Static, SynLizard, SynCrypto and SynEcc units compilation.

Note that such external files are not mandatory to compile the framework source code. There is always a "pure pascal" fallback code available, or use e.g. the official external sqlite3 library. Those .o files were compiled from optimized C/asm, for the best performance, and reduce dependencies or version problems.

Ensure that "Libraries -fFl" in your FPC project options is defined as:
  ..\static\$(TargetCPU)-$(TargetOS)
(replace ..\static by an absolute/relative path to this folder)

If this folder is void (e.g. when retrieved from https://synopse.info/fossil), you can download all the needed sub-folders from http://synopse.info/files/sqlite3fpc.7z

Ensure you keep in synch these binaries with the main framework source code.
Otherwise, SynSQLite3Static will complain about invalid versions, and some random/unexpected errors may occur.

See SQlite3/amalgamation/ReadMe.md for instructions about how to compile the SQlite3 static files after a release from https://sqlite.org


========================
此文件夹包含 FPC 静态链接所需的所有原始二进制文件。

主要用于 SynSQLite3Static、SynLizard、SynCrypto 和 SynEcc 单元编译。

请注意，此类外部文件不是编译框架源代码所必需的。始终有一个“纯 pascal”后备代码可用，或者使用例如官方外部 sqlite3 库。这些 .o 文件是从优化的 C/asm 编译而来的，以获得最佳性能，并减少依赖性或版本问题。

确保 FPC 项目选项中的“Libraries -fFl”定义为：
..\static\$(TargetCPU)-$(TargetOS)
（将 ..\static 替换为此文件夹的绝对/相对路径）

如果此文件夹为空（例如从 https://synopse.info/fossil 检索时），您可以从 http://synopse.info/files/sqlite3fpc.7z 下载所有所需的子文件夹

确保将这些二进制文件与主框架源代码保持同步。
否则，SynSQLite3Static 会抱怨版本无效，并且可能会发生一些随机/意外错误。

有关如何在 https://sqlite.org 发布后编译 SQlite3 静态文件的说明，请参阅 SQlite3/amalgamation/ReadMe.md

