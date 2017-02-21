actor FileStream is OutStream
  """
  Asynchronous access to a File object. Wraps file operations print, write,
  printv and writev. The File will be disposed through File._final.
  """
  let _file: File

  new create(file: File iso) =>
    _file = consume file

  be print(data: ByteSeq) =>
    """
    Print some bytes and insert a newline afterwards.
    """
    try
      _file.print(data)
    end

  be write(data: ByteSeq) =>
    """
    Print some bytes without inserting a newline afterwards.
    """
    try
      _file.write(data)
    end

  be printv(data: ByteSeqIter) =>
    """
    Print an iterable collection of ByteSeqs.
    """
    try
      _file.printv(data)
    end

  be writev(data: ByteSeqIter) =>
    """
    Write an iterable collection of ByteSeqs.
    """
    try
      _file.writev(data)
    end
