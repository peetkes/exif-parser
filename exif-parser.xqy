xquery version "1.0-ml";
(:~
 : Copyright (c) 2018 Peter Kester
 : 
 : Licensed under the Apache License, Version 2.0 (the "License");
 : you may not use this file except in compliance with the License.
 : You may obtain a copy of the License at
 : 
 :        http://www.apache.org/licenses/LICENSE-2.0
 : 
 : Unless required by applicable law or agreed to in writing, software
 : distributed under the License is distributed on an "AS IS" BASIS,
 : WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 : See the License for the specific language governing permissions and
 : limitations under the License.
 :  
 : @author      Peter Kester (peetkes@gmail.com)
 : @version     1.0.0
 : @description This library can be used to extract all exif properties from jpeg images.
 :      To use this library you need to import the module and pass in an image as a binary object.
 :      It will return a map with key-value properties, Two properties contain a map with key-value properties
 :      It is based on the work of miguelrgonzalez
 :      The original gist can be found here: https://gist.github.com/miguelrgonzalez/d8daf7e3840f20b8dcee
 : 
~:)
module namespace exif = "http://peetkes.github.io/exif-parser";

import module namespace exif-consts = "http://peetkes.github.io/exif-consts" at "exif-consts.xqy";

declare option xdmp:mapping "false";

(:~
 : This function extracts all exif and gps properties from the given image
 :
 : @param   $image, image as binary node
 : @return  map containing all exif properties
 :)
declare function exif:parse(
        $image as binary()
) as map:map?
{
    let $magic-number := xs:hexBinary(xdmp:subbinary($image, 1, 2))
    return
        if (fn:string($magic-number) eq 'FFD8')
        then (
            (: it's a jpeg :)
            let $start0 := 3
            (: get first APP block, if App1 then it contains Exif Attribute Information :)
            let $app0-marker := fn:string(xs:hexBinary(xdmp:subbinary($image, $start0, 2)))
            let $app0-size := xdmp:hex-to-integer(fn:string(xs:hexBinary(xdmp:subbinary($image, $start0 + 2, 2))))
            let $app0-name := xdmp:binary-decode(xdmp:subbinary($image, $start0 + 4, 4), "utf-8")
            (: get second APP block, if App1 then it contains Exif Attribute Information :)
            let $start1 := $start0 + $app0-size + 2
            let $app1-marker := fn:string(xs:hexBinary(xdmp:subbinary($image, $start1, 2)))
            let $app1-size := xdmp:hex-to-integer(fn:string(xs:hexBinary(xdmp:subbinary($image, $start1 + 2, 2))))
            let $app1-name := xdmp:binary-decode(xdmp:subbinary($image, $start1 + 4, 4), "utf-8")

            let $app-start :=
                if ($app0-marker eq "FFE1" and $app0-name eq "Exif")
                then $start0
                else if ($app1-marker eq "FFE1" and $app1-name eq "Exif")
                then $start1
                else 0
            let $app-block :=
                if ($app0-marker eq "FFE1" and $app0-name eq "Exif")
                then
                    element app-block {
                        attribute start { $app-start + 2 },
                        attribute size { $app0-size },
                        attribute name { $app0-name },
                        xs:hexBinary(xdmp:subbinary($image, $app-start+2, $app0-size))
                    }
                else if ($app1-marker eq "FFE1" and $app1-name eq "Exif")
                then
                    element app-block {
                        attribute start { $app-start + 2 },
                        attribute size { $app1-size },
                        attribute name { $app1-name },
                        xs:hexBinary(xdmp:subbinary($image, $app-start+2, $app1-size))
                    }
                else ()
            let $jfif-start :=
                if ($app0-marker eq "FFE0" and $app0-name eq "JFIF")
                then $start0
                else 0
            let $jfif-block := 
                if ($app0-marker eq "FFE0" and $app0-name eq "JFIF")
                then
                    element app-block {
                        attribute start { $jfif-start + 2 },
                        attribute size { $app0-size },
                        attribute name { $app0-name },
                        xs:hexBinary(xdmp:subbinary($image, $jfif-start+2, $app0-size))
                    }
                else ()
            let $tiff-header := exif:get-tiff-header($app-block/@start, binary { $app-block })
            let $jfif-header :=
                if ($jfif-start eq 0)
                then ()
                else exif:get-jfif-header($jfif-block/@start, binary { $jfif-block })
            let $fields := exif:extract-fields($image, map:get($tiff-header,"byte-order"), map:get($tiff-header,"start"), map:get($tiff-header,"offset"), $exif-consts:FIELDS)
            return $fields
                =>map:with("ImageSize", xdmp:binary-size($image))
                =>map:with("JfifProps", $jfif-header)
        ) else ()
};

declare private function exif:endianness(
        $binary as binary(),
        $byte-order as xs:string
) as binary()
{
    if ($byte-order eq 'BE')
    then $binary
    else (: LE :)
        let $size := xdmp:binary-size($binary)
        let $result :=
            for $pos in (0 to $size - 1)
            return fn:string(xdmp:subbinary($binary, $size - $pos, 1))
        return binary {xs:hexBinary(fn:string-join($result, ''))}
};

declare private function exif:fetch-short-or-long(
        $byte-order as xs:string,
        $count as xs:integer,
        $size as xs:integer,
        $binary as binary()
) as item()?
{
    let $short :=
        for $i in (1 to $count)
        let $value := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($binary, 1 + ($i - 1)*$size, $size), $byte-order))))
        return $value
    return
        if ($count > 1)
        then fn:string-join($short, ";")
        else $short
};

declare private function exif:fetch-rational(
        $byte-order as xs:string,
        $count as xs:integer,
        $size as xs:integer,
        $binary as binary()
) as item()?
{
    let $rational :=
        for $i in (1 to $count)
        let $rational := binary { xdmp:subbinary($binary, 1 + ($i - 1)*$size, $size) }
        let $numerator := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($rational, 1, 4), $byte-order))))
        let $denominator := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($rational, 5, 4), $byte-order))))
        return
            if ($denominator > 0)
            then fn:string($numerator div $denominator)
            else fn:string(xs:hexBinary($rational))
    return
        if ($count > 1)
        then fn:string-join($rational, ";")
        else $rational
};

declare private function exif:fetch-value(
        $binary as binary(),
        $byte-order as xs:string,
        $type as xs:integer,
        $count as xs:integer,
        $start as xs:integer,
        $offset as binary()
) as item()?
{
    let $size := $exif-consts:TYPES/type[@id eq $type]/@size
    return
        if ($count * $size > 4)
        (: if the value is bigger than 4 bytes will be stored in the data section :)
        then
            let $binary := binary { xdmp:subbinary($binary,
                    $start + xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness($offset, $byte-order)))),
                    $count * $size) }
            return
                if (xdmp:binary-size($binary) > 0)
                then
                    if ($exif-consts:TYPES/type[@id eq  $type and @decode eq 'true'])
                    then xdmp:binary-decode($binary, 'utf8')
                    else if ($exif-consts:TYPES/type[@id eq $type] = ("Rational","SRational"))
                    then exif:fetch-rational($byte-order, $count, $size, $binary)
                    else xs:string(fn:data($binary))
                else ''
        else
            if ($exif-consts:TYPES/type[@id eq  $type and @decode eq 'true'])
            then
                let $ascii-string := exif:get-ascii-string(exif:endianness($offset, $byte-order), xdmp:binary-size($offset))
                return
                    if (fn:empty($ascii-string))
                    then ()
                    else xdmp:binary-decode($ascii-string, 'utf8')
            else if ($exif-consts:TYPES/type[@id eq  $type] = ("Short", "Long"))
            then fetch-short-or-long($byte-order, $count, $size, $offset)
            else xs:string(fn:data(exif:endianness($offset, $byte-order)))
};

(:  gets NULL terminated asci string :)
declare private function exif:get-ascii-string(
    $ascii-string as binary(),
    $size as xs:integer
) as binary()?
{
    if (xdmp:hex-to-integer(xs:string($ascii-string)) eq 0)
    then ()
    else binary {
        fn:string-join(
            for $i in 1 to $size
            let $byte := substring(xs:string($ascii-string), 2 * ($i - 1) + 1, 2)
            where $byte ne "00"
            return $byte,
            ""
        )
    }
};

declare private function exif:extract-fields(
        $image as binary(),
        $byte-order as xs:string,
        $start as xs:integer,
        $offset as xs:integer,
        $fieldNames as map:map
) as map:map
{
    let $map := map:map()
    let $field-count-bin := binary { xs:hexBinary(xdmp:subbinary($image, $start + $offset, 2))}
    let $field-count := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness($field-count-bin,$byte-order))))
    let $_ := (
        for $cnt in 1 to $field-count
        let $field := binary { xdmp:subbinary($image, $start + $offset + 2 + ($cnt - 1)*12, 12) }
        let $tag-id := exif:endianness(xdmp:subbinary($field, 1, 2), $byte-order)
        let $type := exif:endianness(xdmp:subbinary($field, 3, 2), $byte-order)
        let $count := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($field, 5, 4), $byte-order))))
        let $value-offset := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($field, 9, 4), $byte-order))))
        let $offset-to-value := xdmp:subbinary($field, 9, 4)
        let $value := exif:fetch-value($image, $byte-order, xdmp:hex-to-integer(fn:string(xs:hexBinary($type))), $count, $start, $offset-to-value)
        let $name := map:get($fieldNames, fn:string(xs:hexBinary($tag-id)))
        return map:put($map, $name,
                if ($name = ('ExifOffset','GPSInfo'))
                then map:map()
                =>map:with("value-offset", $value-offset)
                => map:with("value", $value)
                else $value)
        (:)    let $_ := :),
        if (map:contains($map,'ExifOffset'))
        then (
            map:put($map, "ExifProps", exif:extract-fields($image, $byte-order, $start, map:get(map:get($map,'ExifOffset'),'value-offset'), $fieldNames)),
            map:delete($map, 'ExifOffset')
        )
        else (),
        if (map:contains($map,'GPSInfo'))
        then (
            map:put($map, "GPSProps", exif:extract-fields($image, $byte-order, $start, map:get(map:get($map,'GPSInfo'),'value-offset'), $exif-consts:GPS-FIELDS)),
            map:delete($map, 'GPSInfo')
        )
        else ()
    )
    return $map
};

declare function exif:get-tiff-header(
        $offset as xs:integer,
        $image as binary()
) as map:map
{
    let $tiff-header-start := 9
    let $tiff-header := binary { xs:hexBinary(xdmp:subbinary($image, $tiff-header-start, 8)) }
    let $byte-order :=
        if (fn:matches(fn:string(xs:hexBinary($tiff-header)), '^4D4D.*'))
        then 'BE' (: Big Endian :)
        else 'LE' (: Assume 4949 Little Endian :)
    (: see http://partners.adobe.com/public/developer/en/tiff/TIFF6.pdf :)
    let $idf0-offset := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(binary { xs:hexBinary(xdmp:subbinary($tiff-header, 5, 4))}, $byte-order))))
    return map:map()
    => map:with("header", xs:hexBinary($tiff-header))
    => map:with("byte-order", $byte-order)
    => map:with("start", $tiff-header-start + $offset - 1)
    => map:with("offset", $idf0-offset)
};

declare function exif:get-jfif-header(
  $start as xs:integer,
  $binary as binary()
) as map:map
{
(:00104A46494600010101012C012C0000:)
    let $versionMajor := xdmp:subbinary($binary, 8, 1)
    let $versionMinor := xdmp:subbinary($binary, 9, 1)
    let $units := xdmp:subbinary($binary, 10, 1)
    let $xDensity := xdmp:subbinary($binary, 11, 2)
    let $yDensity := xdmp:subbinary($binary, 13, 2)
    return map:map()
    => map:with("JfifVersionMajor", $versionMajor/fn:string())
    => map:with("JfifVersionMinor", $versionMinor/fn:string())
    => map:with("ResolutionUnit", xdmp:hex-to-integer($units/fn:string()))
    => map:with("XResolution", xdmp:hex-to-integer($xDensity/fn:string()))
    => map:with("YResolution", xdmp:hex-to-integer($yDensity/fn:string()))
};

