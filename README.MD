# EXIF-Parser

This library can be used to extract all exif properties from jpeg images.
To use this library you need to import the module and pass in an image as a binary object.
It will return a map with key-value properties, Two properties contain a map with key-value properties

* ExifProps
* GPSProps

It is based on the work of [miguelrgonzalez](https://github.com/miguelrgonzalez)
The original gist can be found [here](https://gist.github.com/miguelrgonzalez/d8daf7e3840f20b8dcee)

## Usage

```xquery
let $image-uri := "some location on disk"
return exif:parse(xdmp:external-binary($image-uri))
```
or when images reside in MarkLogic content database
```xquery
let $image-uri := "some location in database"
return exif:parse(fn:doc($image-uri))
```

This will result in something like below

```xml
<map:map xmlns:map="http://marklogic.com/xdmp/map" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xs="http://www.w3.org/2001/XMLSchema">
	<map:entry key="Software">
		<map:value xsi:type="xs:string">11.1.2</map:value>
	</map:entry>
	<map:entry key="Orientation">
		<map:value xsi:type="xs:integer">6</map:value>
	</map:entry>
	<map:entry key="XResolution">
		<map:value xsi:type="xs:string">72</map:value>
	</map:entry>
	<map:entry key="YResolution">
		<map:value xsi:type="xs:string">72</map:value>
	</map:entry>
	<map:entry key="Model">
		<map:value xsi:type="xs:string">iPhone 7</map:value>
	</map:entry>
	<map:entry key="ResolutionUnit">
		<map:value xsi:type="xs:integer">2</map:value>
	</map:entry>
	<map:entry key="ModifyDate">
		<map:value xsi:type="xs:string">2017:11:27 18:00:31</map:value>
	</map:entry>
	<map:entry key="ExifProps">
		<map:value>
			<map:map>
				<map:entry key="LensModel">
					<map:value xsi:type="xs:string">iPhone 7 back camera 3.99mm f/1.8</map:value>
				</map:entry>
				....
			</map:map>
		</map:value>
	</map:entry>
	<map:entry key="Make">
		<map:value xsi:type="xs:string">Apple</map:value>
	</map:entry>
	<map:entry key="GPSProps">
		<map:value>
			<map:map>
				<map:entry key="GPSDestBearingRef">
					<map:value xsi:type="xs:string">T</map:value>
				</map:entry>
				....
			</map:map>
		</map:value>
	</map:entry>
</map:map>
```