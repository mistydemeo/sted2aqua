#!/usr/bin/ruby

ARGV.each { |fn|
  next if fn =~ /_conv\.txt/
  fp = open(fn, "rb")
  d = fp.read
  fp.close
  s = ""
  x = 0
  d.each_byte { |n|
    if n == 9
      dx = 8 - x % 8
      s += " " * dx
      x += dx
    elsif n == 13
      next
    elsif n == ?<
      s += "&lt;"
      x += 1
    elsif n == ?>
      s += "&gt;"
      x += 1
    elsif n == ?&
      s += "&amp;"
      x += 1
    else
      s += n.chr
      if n < 32
        x = 0
      else
        x += 1
      end
    end
  }
  fnnew = fn.sub(/\.\w+$/, "_conv.html")
  fp = open(fnnew, "wb")
  fp.write("<pre>\n")
  fp.write(s)
  fp.write("</pre>\n")
  fp.close
}

