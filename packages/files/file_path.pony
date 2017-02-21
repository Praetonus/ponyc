use "time"

interface WalkHandler
  """
  A handler for `FilePath.walk`.
  """
  fun ref apply(dir_path: FilePath, dir_entries: Array[String] ref)

class val FilePath
  """
  A FilePath represents a capability to access a path. The path will be
  represented as an absolute path and a set of capabilities for operations on
  that path.
  """
  let path: String
  let caps: FileCaps = FileCaps

  new val create(base: (FilePath | AmbientAuth), path': String,
    caps': FileCaps val = recover val FileCaps.>all() end) ? FileError
  =>
    """
    Create a new path. The caller must either provide the root capability or an
    existing FilePath.

    If the root capability is provided, path' will be relative to the program's
    working directory. Otherwise, it will be relative to the existing FilePath,
    and the existing FilePath must be a prefix of the resulting path.

    The resulting FilePath will have capabilities that are the intersection of
    the supplied capabilities and the capabilities on the parent.
    """
    caps.union(caps')

    match base
    | let b: FilePath =>
      if not b.caps(FileLookup) then
        error FileError
      end

      path = Path.join(b.path, path')
      caps.intersect(b.caps)

      if not path.at(b.path, 0) then
        error FileError
      end
    | let b: AmbientAuth =>
      path = Path.abs(path')
    else
      error FileError
    end

  new val mkdtemp(base: (FilePath | AmbientAuth), prefix: String = "",
    caps': FileCaps val = recover val FileCaps.>all() end) ? FileErrNo
  =>
    """
    Create a temporary directory and returns a path to it. The directory's name
    will begin with `prefix`. The caller must either provide the root
    capability or an existing FilePath.

    If AmbientAuth is provided, pattern will be relative to the program's
    working directory. Otherwise, it will be relative to the existing
    FilePath, and the existing FilePath must be a prefix of the resulting path.

    The resulting FilePath will have capabilities that are the intersection of
    the supplied capabilities and the capabilities on the base.
    """
    (let dir, let pre) = Path.split(prefix)
    let parent = FilePath(base, dir)

    parent.mkdir()

    var temp = FilePath(parent, pre + Path.random())
    var ok = false

    while not ok do
      try
        temp.mkdir(true)
        ok = true
      else
        temp = FilePath(parent, pre + Path.random())
      end
    end

    caps.union(caps')
    caps.intersect(temp.caps)
    path = temp.path

  new val _create(path': String, caps': FileCaps val) =>
    """
    Internal constructor.
    """
    path = path'
    caps.union(caps')

  fun val join(path': String,
    caps': FileCaps val = recover val FileCaps.>all() end): FilePath
    ? FileError
  =>
    """
    Return a new path relative to this one.
    """
    create(this, path', caps')

  fun val walk(handler: WalkHandler ref, follow_links: Bool = false) =>
    """
    Walks a directory structure starting at this.

    `handler(dir_path, dir_entries)` will be called for each directory
    starting with this one.  The handler can control which subdirectories are
    expanded by removing them from the `dir_entries` list.
    """
    try
      var entries: Array[String] ref = Directory(this).entries()
      handler(this, entries)
      for e in entries.values() do
        let p = this.join(e)
        if not follow_links and FileInfo(p).symlink then
          continue
        end
        p.walk(handler, follow_links)
      end
    else
      return
    end

  fun val canonical(): FilePath ? FileError =>
    """
    Return the equivalent canonical absolute path. Raise an error if there
    isn't one.
    """
    _create(Path.canonical(path), caps)

  fun val exists(): Bool =>
    """
    Returns true if the path exists. Returns false for a broken symlink.
    """
    try
      not FileInfo(this).broken
    else
      false
    end

  fun val mkdir(must_create: Bool = false) ? FileErrNo =>
    """
    Creates the directory. Will recursively create each element. Returns true
    if the directory exists when we're done, false if it does not. If we do not
    have the FileStat permission, this will return false even if the directory
    does exist.
    """
    if not caps(FileMkdir) then
      error FileNoCapability
    end

    var offset: ISize = 0

    repeat
      let element = try
        offset = path.find(Path.sep(), offset) + 1
        path.substring(0, offset - 1)
      else
        offset = -1
        path
      end

      if element.size() > 0 then
        let r = ifdef windows then
          @_mkdir[I32](element.cstring())
        else
          @mkdir[I32](element.cstring(), U32(0x1FF))
        end

        if r != 0 then
          if @pony_os_errno[I32]() != @pony_os_eexist[I32]() then
            error _FileDes.get_error()
          end

          if must_create and (offset < 0) then
            error FileError
          end
        end
      end
    until offset < 0 end

    if not FileInfo(this).directory then
      error FileError
    end

  fun val remove() ? FileErrNo =>
    """
    Remove the file or directory. The directory contents will be removed as
    well, recursively. Symlinks will be removed but not traversed.
    """
    if not caps(FileRemove) then
      error FileNoCapability
    end

    let info = FileInfo(this)

    if info.directory and not info.symlink then
      let directory = Directory(this)

      for entry in directory.entries().values() do
        join(entry).remove()
      end
    end

    let ok = ifdef windows then
      if info.directory and not info.symlink then
        0 == @_rmdir[I32](path.cstring())
      else
        0 == @_unlink[I32](path.cstring())
      end
    else
      if info.directory and not info.symlink then
        0 == @rmdir[I32](path.cstring())
      else
        0 == @unlink[I32](path.cstring())
      end
    end

    if not ok then
      error _FileDes.get_error()
    end

  fun rename(new_path: FilePath) ? FileErrNo =>
    """
    Rename a file or directory.
    """
    if not caps(FileRename) or not new_path.caps(FileCreate) then
      error FileNoCapability
    end

    if @rename[I32](path.cstring(), new_path.path.cstring()) != 0 then
      error _FileDes.get_error()
    end

  fun symlink(link_name: FilePath) ? FileErrNo =>
    """
    Create a symlink to a file or directory.
    """
    if not caps(FileLink) or not link_name.caps(FileCreate) then
      error FileNoCapability
    end

    let ok = ifdef windows then
      0 != @CreateSymbolicLink[U8](link_name.path.cstring(),
        path.cstring())
    else
      0 == @symlink[I32](path.cstring(),
        link_name.path.cstring())
    end

    if not ok then
      error _FileDes.get_error()
    end

  fun chmod(mode: FileMode box) ? FileErrNo =>
    """
    Set the FileMode for a path.
    """
    if not caps(FileChmod) then
      error FileNoCapability
    end

    let m = mode._os()

    let ok = ifdef windows then
      0 == @_chmod[I32](path.cstring(), m)
    else
      0 == @chmod[I32](path.cstring(), m)
    end

    if not ok then
      error _FileDes.get_error()
    end

  fun chown(uid: U32, gid: U32) ? FileErrNo =>
    """
    Set the owner and group for a path. Does nothing on Windows.
    """
    ifdef not windows then
      if not caps(FileChown) then
        error FileNoCapability
      end

      if @chown[I32](path.cstring(), uid, gid) != 0 then
        error _FileDes.get_error()
      end
    end

  fun touch() ? FileErrNo =>
    """
    Set the last access and modification times of a path to now.
    """
    set_time(Time.now(), Time.now())

  fun set_time(atime: (I64, I64), mtime: (I64, I64)) ? FileErrNo =>
    """
    Set the last access and modification times of a path to the given values.
    """
    if not caps(FileTime) then
      error FileNoCapability
    end

    let ok = ifdef windows then
      var tv: (I64, I64) = (atime._1, mtime._1)
      0 == @_utime64[I32](path.cstring(), addressof tv)
    else
      var tv: (ILong, ILong, ILong, ILong) =
        (atime._1.ilong(), atime._2.ilong() / 1000,
          mtime._1.ilong(), mtime._2.ilong() / 1000)
      0 == @utimes[I32](path.cstring(), addressof tv)
    end

    if not ok then
      error _FileDes.get_error()
    end
