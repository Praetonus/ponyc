use "time"
use "capsicum"

primitive _EBADF
  fun apply(): I32 => 9

primitive _EEXIST
  fun apply(): I32 => 17

primitive _EACCES
  fun apply(): I32 => 13

primitive _FileDes
  """
  Convenience operations on file descriptors.
  """
  fun chmod(fd: I32, path: FilePath, mode: FileMode box) ? FileErrNo =>
    """
    Set the FileMode for this fd.
    """
    if fd == - 1 then
      return
    end

    if not path.caps(FileChmod) then
      error FileNoCapability
    end

    ifdef windows then
      path.chmod(mode)
    else
      if @fchmod[I32](fd, mode._os()) != 0 then
        error get_error()
      end
    end

  fun chown(fd: I32, path: FilePath, uid: U32, gid: U32) ? FileErrNo =>
    """
    Set the owner and group for this file. Does nothing on Windows.
    """
    ifdef not windows then
      if (fd == -1) then
        return
      end

      if not path.caps(FileChown) then
        error FileNoCapability
      end

      if @fchown[I32](fd, uid, gid) != 0 then
        error get_error()
      end
    end

  fun touch(fd: I32, path: FilePath) ? FileErrNo =>
    """
    Set the last access and modification times of the file to now.
    """
    set_time(fd, path, Time.now(), Time.now())

  fun set_time(fd: I32, path: FilePath, atime: (I64, I64),
    mtime: (I64, I64)) ? FileErrNo
  =>
    """
    Set the last access and modification times of the file to the given values.
    """
    if (fd == -1) then
      return
    end

    if not path.caps(FileTime) then
      error FileNoCapability
    end

    ifdef windows then
      path.set_time(atime, mtime)
    else
      var tv: (ILong, ILong, ILong, ILong) =
        (atime._1.ilong(), atime._2.ilong() / 1000,
          mtime._1.ilong(), mtime._2.ilong() / 1000)
      if @futimes[I32](fd, addressof tv) != 0 then
        error get_error()
      end
    end

  fun set_rights(fd: I32, path: FilePath, writeable: Bool = true)
    ? FileNoCapability
  =>
    """
    Set the Capsicum rights on the file descriptor.
    """
    ifdef freebsd or "capsicum" then
      if fd != -1 then
        let cap = CapRights.from(path.caps)

        if not writeable then
          cap.unset(Cap.write())
        end

        if not cap.limit(fd) then
          error FileNoCapability
        end
      end
    end

  fun get_error(): FileErrNo =>
    """
    Fetch errno from the OS.
    """
    let os_errno = @pony_os_errno[I32]()
    match os_errno
    | _EBADF() => return FileBadFileNumber
    | _EEXIST() => return FileExists
    | _EACCES() => return FilePermissionDenied
    else
      return FileError
    end
