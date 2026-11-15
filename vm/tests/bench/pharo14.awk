# Chunk-format sources as Pharo 14 files them in: one method per methodsFor: preamble, followed by an empty chunk.
# Here a method ends with a line "!", a category with "! !" or with a line " !" after the last "!". Pharo 12 reads both.
/^!.* methodsFor: .*!$/ { p = $0; print; next }
p != "" && $0 == "!" { print "! !"; pend = 1; next }
pend && $0 == " !" { pend = 0; p = ""; next }
pend && $0 != "" { print p; pend = 0 }
$0 == "! !" { p = "" }
{ print }
