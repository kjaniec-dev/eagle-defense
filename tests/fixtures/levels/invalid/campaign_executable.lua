-- Test fixture (G2 plan §11, §15): executable code instead of data
-- expect: level:
return os.execute("echo pwned")
