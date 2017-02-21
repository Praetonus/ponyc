use "time"

use @ponyint_o_rdonly[I32]()
use @ponyint_o_rdwr[I32]()
use @ponyint_o_creat[I32]()
use @ponyint_o_trunc[I32]()
use @ponyint_o_directory[I32]()
use @ponyint_o_cloexec[I32]()
use @ponyint_at_removedir[I32]()
use @unlinkat[I32](fd: I32, target: Pointer[U8] tag, flags: I32)

primitive _DirectoryHandle
primitive _DirectoryEntry

class Directory
  """
  Operations on a directory.

  The directory-relative functions (open, etc) use the *at interface on FreeBSD
  and Linux. This isn't available on OS X prior to 10.10, so it is not used. On
  FreeBSD, this allows the directory-relative functions to take advantage of
  Capsicum.
  """
  let path: FilePath
  var _fd: I32 = -1
  // We don't need a file descriptor in Windows. However we do still need to
  // know whether we've disposed of this object, so we use the _fd to indicate
  // this.
  // 0 => not yet disposed of.
  // -1 => disposed of.

  new create(from: FilePath) ? FileErrNo =>
    """
    This will raise an error if the path doesn't exist or it is not a
    directory, or if FileRead or FileStat permission isn't available.
    """
    if not from.caps(FileRead) then
      error FileNoCapability
    end

    if not FileInfo(from).directory then
      error FileError
    end

    path = from

    ifdef posix then
      _fd = @open[I32](from.path.cstring(),
        @ponyint_o_rdonly() or @ponyint_o_directory() or @ponyint_o_cloexec())

      if _fd == -1 then
        error _FileDes.get_error()
      end
    elseif windows then
      _fd = 0
    else
      compile_error "unsupported platform"
    end

    _FileDes.set_rights(_fd, path)

  new iso _relative(path': FilePath, fd': I32) =>
    """
    Internal constructor. Capsicum rights are already set by inheritence.
    """
    path = path'
    _fd = fd'

  fun entries(): Array[String] iso^ ? FileErrNo =>
    """
    The entries will include everything in the directory, but it is not
    recursive. The path for the entry will be relative to the directory, so it
    will contain no directory separators. The entries will not include "." or
    "..".
    """
    if not path.caps(FileRead) then
      error FileNoCapability
    end

    if _fd == -1 then
      error FileError
    end

    let path' = path.path
    let fd' = _fd

    recover
      let list = Array[String]

      ifdef posix then
        let h = ifdef linux or freebsd then
          let fd = @openat[I32](fd', ".".cstring(),
            @ponyint_o_rdonly() or @ponyint_o_directory() or @ponyint_o_cloexec())
          @fdopendir[Pointer[_DirectoryHandle]](fd)
        else
          @opendir[Pointer[_DirectoryHandle]](path'.cstring())
        end

        if h.is_null() then
          error _FileDes.get_error()
        end

        while true do
          let p = @ponyint_unix_readdir[Pointer[U8] iso^](h)
          if p.is_null() then break end
          list.push(recover String.from_cstring(consume p) end)
        end

        @closedir[I32](h)
      elseif windows then
        var find = @ponyint_windows_find_data[Pointer[_DirectoryEntry]]()
        let search = path' + "\\*"
        let h = @FindFirstFileA[Pointer[_DirectoryHandle]](
          search.cstring(), find)

        if h.usize() == -1 then
          error FileError
        end

        repeat
          let p = @ponyint_windows_readdir[Pointer[U8] iso^](find)

          if not p.is_null() then
            list.push(recover String.from_cstring(consume p) end)
          end
        until not @FindNextFileA[Bool](h, find) end

        @FindClose[Bool](h)
        @free[None](find)
      else
        compile_error "unsupported platform"
      end

      consume list
    end

  fun open(target: String): Directory iso^ ? FileErrNo =>
    """
    Open a directory relative to this one. Raises an error if the path is not
    within this directory hierarchy.
    """
    if _fd == -1 then
      error FileError
    end

    let path' = FilePath(path, target, path.caps)

    ifdef linux or freebsd then
      let fd' = @openat[I32](_fd, target.cstring(),
        @ponyint_o_rdonly() or @ponyint_o_directory() or @ponyint_o_cloexec())
      _relative(path', fd')
    else
      recover create(path') end
    end

  fun mkdir(target: String) ? FileErrNo =>
    """
    Creates a directory relative to this one. Returns false if the path is
    not within this directory hierarchy or if FileMkdir permission is missing.
    """
    if _fd == -1 then
      error FileError
    end

    if not path.caps(FileMkdir) or not path.caps(FileLookup) then
      error FileNoCapability
    end

    let path' = FilePath(path, target, path.caps)

    ifdef linux or freebsd then
      var offset: ISize = 0

      repeat
        let element = try
          offset = target.find(Path.sep(), offset) + 1
          target.substring(0, offset - 1)
        else
          offset = -1
          target
        end

        @mkdirat[I32](_fd, element.cstring(), U32(0x1FF))
      until offset < 0 end

      FileInfo(path').directory
    else
      path'.mkdir()
    end

  fun create_file(target: String): File iso^ ? FileErrNo =>
    """
    Open for read/write, creating if it doesn't exist, preserving the contents
    if it does exist.
    """
    if _fd == -1 then
      error FileError
    end

    if
      not path.caps(FileCreate) or
      not path.caps(FileRead) or
      not path.caps(FileWrite)
    then
      error FileNoCapability
    end

    let path' = FilePath(path, target, path.caps)

    ifdef linux or freebsd then
      let fd' = @openat[I32](_fd, target.cstring(),
        @ponyint_o_rdwr() or @ponyint_o_creat() or @ponyint_o_cloexec(),
        I32(0x1B6))
      recover File._descriptor(fd', path') end
    else
      recover File(path') end
    end

  fun open_file(target: String): File iso^ ? FileErrNo =>
    """
    Open for read only, failing if it doesn't exist.
    """
    if _fd == -1 then
      error FileError
    end

    if not path.caps(FileRead) then
      error FileNoCapability
    end

    let path' = FilePath(path, target, path.caps - FileWrite)

    ifdef linux or freebsd then
      let fd' = @openat[I32](_fd, target.cstring(),
        @ponyint_o_rdonly() or @ponyint_o_cloexec(), I32(0x1B6))
      recover File._descriptor(fd', path') end
    else
      recover File(path') end
    end

  fun info(): FileInfo ? FileErrNo =>
    """
    Return a FileInfo for this directory. Raise an error if the fd is invalid
    or if we don't have FileStat permission.
    """
    FileInfo._descriptor(_fd, path)

  fun chmod(mode: FileMode box) ? FileErrNo =>
    """
    Set the FileMode for this directory.
    """
    _FileDes.chmod(_fd, path, mode)

  fun chown(uid: U32, gid: U32) ? FileErrNo =>
    """
    Set the owner and group for this directory. Does nothing on Windows.
    """
    _FileDes.chown(_fd, path, uid, gid)

  fun touch() ? FileErrNo =>
    """
    Set the last access and modification times of the directory to now.
    """
    _FileDes.touch(_fd, path)

  fun set_time(atime: (I64, I64), mtime: (I64, I64)) ? FileErrNo =>
    """
    Set the last access and modification times of the directory to the given
    values.
    """
    _FileDes.set_time(_fd, path, atime, mtime)

  fun infoat(target: String): FileInfo ? FileErrNo =>
    """
    Return a FileInfo for some path relative to this directory.
    """
    if _fd == -1 then
      error FileError
    end

    if not path.caps(FileStat) or not path.caps(FileLookup) then
      error FileNoCapability
    end

    let path' = FilePath(path, target, path.caps)

    ifdef linux or freebsd then
      FileInfo._relative(_fd, path', target)
    else
      FileInfo(path')
    end

  fun chmodat(target: String, mode: FileMode box) ? FileErrNo =>
    """
    Set the FileMode for some path relative to this directory.
    """
    if _fd == -1 then
      error FileError
    end

    if not path.caps(FileChmod) or not path.caps(FileLookup) then
      error FileNoCapability
    end

    let path' = FilePath(path, target, path.caps)

    ifdef linux or freebsd then
      if @fchmodat[I32](_fd, target.cstring(), mode._os(), I32(0)) != 0 then
        error _FileDes.get_error()
      end
    else
      path'.chmod(mode)
    end

  fun chownat(target: String, uid: U32, gid: U32) ? FileErrNo =>
    """
    Set the FileMode for some path relative to this directory.
    """
    if _fd == -1 then
      error FileError
    end

    if not path.caps(FileChown) or not path.caps(FileLookup) then
      error FileNoCapability
    end

    let path' = FilePath(path, target, path.caps)

    ifdef linux or freebsd then
      if @fchownat[I32](_fd, target.cstring(), uid, gid, I32(0)) != 0 then
        error _FileDes.get_error()
      end
    else
      path'.chown(uid, gid)
    end

  fun touchat(target: String) ? FileErrNo =>
    """
    Set the last access and modification times of the directory to now.
    """
    set_time_at(target, Time.now(), Time.now())

  fun set_time_at(target: String, atime: (I64, I64), mtime: (I64, I64))
    ? FileErrNo
  =>
    """
    Set the last access and modification times of the directory to the given
    values.
    """
    if _fd == -1 then
      error FileError
    end

    if not path.caps(FileChown) or not path.caps(FileLookup) then
      error FileNoCapability
    end

    let path' = FilePath(path, target, path.caps)

    ifdef linux or freebsd then
      var tv: (ILong, ILong, ILong, ILong) =
        (atime._1.ilong(), atime._2.ilong() / 1000,
          mtime._1.ilong(), mtime._2.ilong() / 1000)
      if @futimesat[I32](_fd, target.cstring(), addressof tv) != 0 then
        error _FileDes.get_error()
      end
    else
      path'.set_time(atime, mtime)
    end

  fun symlink(source: FilePath, link_name: String) ? FileErrNo =>
    """
    Link the source path to the link_name, where the link_name is relative to
    this directory.
    """
    if _fd == -1 then
      error FileError
    end

    if
      not path.caps(FileLink) or
      not path.caps(FileLookup) or
      not path.caps(FileCreate) or
      not source.caps(FileLink)
    then
      error FileNoCapability
    end

    let path' = FilePath(path, link_name, path.caps)

    ifdef linux or freebsd then
      if @symlinkat[I32](source.path.cstring(), _fd, link_name.cstring()) == 0
      then
        error _FileDes.get_error()
      end
    else
      source.symlink(path')
    end

  fun remove(target: String) ? FileErrNo =>
    """
    Remove the file or directory. The directory contents will be removed as
    well, recursively. Symlinks will be removed but not traversed.
    """
    if _fd == -1 then
      error FileError
    end

    if not path.caps(FileLookup) or not path.caps(FileRemove) then
      error FileNoCapability
    end

    let path' = FilePath(path, target, path.caps)

    ifdef linux or freebsd then
      let fi = FileInfo(path')

      let ok = if fi.directory and not fi.symlink then
        let directory = open(target)

        for entry in directory.entries().values() do
          directory.remove(entry)
        end

        0 == @unlinkat(_fd, target.cstring(), @ponyint_at_removedir())
      else
        0 == @unlinkat(_fd, target.cstring(), 0)
      end

      if not ok then
        error _FileDes.get_error()
      end
    else
      path'.remove()
    end

  fun rename(source: String, to: Directory box, target: String) ? FileErrNo =>
    """
    Rename source (which is relative to this directory) to target (which is
    relative to the `to` directory).
    """
    if (_fd == -1) or (to._fd == -1) then
      error FileError
    end

    if
      not path.caps(FileLookup) or
      not path.caps(FileRename) or
      not to.path.caps(FileLookup) or
      not to.path.caps(FileCreate)
    then
      error FileNoCapability
    end

    let path' = FilePath(path, source, path.caps)
    let path'' = FilePath(to.path, target, to.path.caps)

    ifdef linux or freebsd then
      if @renameat[I32](_fd, source.cstring(), to._fd, target.cstring()) != 0
      then
        error _FileDes.get_error()
      end
    else
      path'.rename(path'')
    end

  fun ref dispose() =>
    """
    Close the directory.
    """
    if _fd != -1 then
      ifdef posix then
        @close[I32](_fd)
      end

      _fd = -1
    end

  fun _final() =>
    """
    Close the file descriptor.
    """
    if _fd != -1 then
      ifdef posix then
        @close[I32](_fd)
      end
    end
