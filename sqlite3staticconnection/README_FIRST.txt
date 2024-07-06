TSQLite3StaticConnection

This is a duplicate implementation of TSQLite3Connection that links
statically against sqlite3.

** LICENSE **
Modifications made by Kurt Fitzner <kurt@va1der.ca> are released into
the public domain.  Copyright to component is as follows:

- TSQLite3StaticConnection was made with modified sources from the Free Pascal
  Classes Library (FCL).  The FCL is distributed under the GNU LGPL with
  a linking exception.  see COPYING.FPL for more details
- SQLite3 is donated to the public domain
- In Windows compiling requires libgcc which is licensed under the GPL plus
  GCC Runtime Library Exception
- In Windows compiling also requires libkernel32.a which is just an import
  library for the Windows libkernel32.dll

In short, code that you write that uses this component should be able to be
released under any license you like.  If you make and release modified
versions of this component, then you need to release it under the terms of
the GNU LGPL.
  
  
** CHANGES **
2 Dec 2016 - Kurt Fitzner <kurt@va1der.ca>
 - Initial version 0.5.0.0 released for FPC 3.0.0
 
** BUILDING **
WINDOWS:
You need to provide several static libraries for Lazarus to build with this
component:
- libsqlite3.a
- libgcc.a
- libmsvcrt.a
- libkernel32.a

libsqlite3.a
This can quite easily be compiled with MinGW.  I used msys2 to make my MinGW
installation since it supports building both 32 and 64 bit targets.  See
https://sourceforge.net/p/msys2/wiki/MSYS2%20installation/

SQLite3 is, happily, released into the public domain and so the source
is included with this component under src/sqlite-amalgamation-3150100. What
more, it is released as a single, monolithic source file that requires no
complicated building.  Simply go to the source directory and issue the
following two commands:
$ gcc -O3 -c sqlite3.c
$ ar rcs libsqlite.a sqlite3.o

And that is it.  Once done, copy to either lib/i386-win32 for 32 bit or
lib/x86_64-win64 for 64 bit.

However, do note that using gcc to compile it means you also need to include
some helper libraries from MinGW.  You need to supply libgcc.a, libmsvcrt.a,
and libkernel32.a. 

libgcc.a
For 32 bit copy this from <MINGW>\mingw32\lib\gcc\i686-w64-mingw32\6.2.0
For 64 bit copy this from <MINGW>\mingw64\lib\gcc\i686-w64-mingw32\6.2.0

libmsvcrt.a
libkernel32.s 
For 32 bit copy these from <MINGW>\mingw32\i686-w64-mingw32\lib
For 64 bit copy these from <MINGW>\mingw64\i686-w64-mingw32\lib

LINUX:
Not tested, but probably will work either out of the box, or by copying
wherever your already installed static libraries are.

** NOTES and CONTACT **
This was built with the components from FPC 3.0.0 under Lazarus 1.6.2.  Your
mileage may vary under different versions.  Notably, I am not actively
maintaining this for all sorts of different versions.  Whichever version of
FPC and Lazarus I'm using will get this component worked for it.  It really
shouldn't be very difficult to replicate my work to roll your own in case
you want to use this with a different version of FPC or Lazarus.

This "Works for Me"™ - if you run into troubles building or using it, I am
happy to consult, but may or may not be able to help.  Also, I work for the
Royal Canadian Navy as my primary job, so if you don't get a reply, I may be
out of the country and unable to respond for between a week and six months.

Feel free to contact me at kurt@va1der.ca
