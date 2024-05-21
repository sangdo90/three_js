import "dart:io";
import "dart:typed_data";

import "package:flutter_gl/flutter_gl.dart";
import "package:three_js_core/three_js_core.dart";
import "package:three_js_core_loaders/three_js_core_loaders.dart";
import "package:three_js_math/three_js_math.dart";

/**
 * Description: A THREE loader for PLY ASCII files (known as the Polygon
 * File Format or the Stanford Triangle Format).
 *
 * Limitations: ASCII decoding assumes file is UTF-8.
 *
 * Usage:
 *	const loader = PLYLoader();
 *	loader.load('./models/ply/ascii/dolphins.ply', function (geometry) {
 *
 *		scene.add( THREE.Mesh( geometry ) );
 *
 *	} );
 *
 * If the PLY file uses non standard property names, they can be mapped while
 * loading. For example, the following maps the properties
 * “diffuse_(red|green|blue)” in the file to standard color names.
 *
 * loader.setPropertyNameMapping( {
 *	diffuse_red: 'red',
 *	diffuse_green: 'green',
 *	diffuse_blue: 'blue'
 * } );
 *
 * Custom properties outside of the defaults for position, uv, normal
 * and color attributes can be added using the setCustomPropertyNameMapping method.
 * For example, the following maps the element properties “custom_property_a”
 * and “custom_property_b” to an attribute “customAttribute” with an item size of 2.
 * Attribute item sizes are set from the number of element properties in the property array.
 *
 * loader.setCustomPropertyNameMapping( {
 *	customAttribute: ['custom_property_a', 'custom_property_b'],
 * } );
 *
 */

final _color = Color();

class PLYLoader extends Loader {
  late final FileLoader _loader;

  /// [manager] — The [loadingManager] for the loader to use. Default is [DefaultLoadingManager].
	PLYLoader([super.manager]){
		_loader = FileLoader(manager);
  }

  @override
  void dispose(){
    super.dispose();
    _loader.dispose();
  }
  
  void _init(){
		_loader.setPath(path);
		_loader.setResponseType('arraybuffer');
		_loader.setRequestHeader(requestHeader);
		_loader.setWithCredentials(withCredentials);
  }

  @override
  Future<BufferGeometry?> fromNetwork(Uri uri) async{
    _init();
    ThreeFile? tf = await _loader.fromNetwork(uri);
    return tf == null?null:_parse(tf.data);
  }
  @override
  Future<BufferGeometry> fromFile(File file) async{
    _init();
    ThreeFile tf = await _loader.fromFile(file);
    return _parse(tf.data);
  }
  @override
  Future<BufferGeometry?> fromPath(String filePath) async{
    _init();
    ThreeFile? tf = await _loader.fromPath(filePath);
    return tf == null?null:_parse(tf.data);
  }
  @override
  Future<BufferGeometry> fromBlob(Blob blob) async{
    _init();
    ThreeFile tf = await _loader.fromBlob(blob);
    return _parse(tf.data);
  }
  @override
  Future<BufferGeometry?> fromAsset(String asset, {String? package}) async{
    _init();
    ThreeFile? tf = await _loader.fromAsset(asset,package: package);
    return tf == null?null:_parse(tf.data);
  }
  @override
  Future<BufferGeometry> fromBytes(Uint8List bytes) async{
    _init();
    ThreeFile tf = await _loader.fromBytes(bytes);
    return _parse(tf.data);
  }

  Map<String,dynamic> propertyNameMapping = {};
  Map<String,dynamic> customPropertyMapping = {};

	setPropertyNameMapping( mapping ) {
		propertyNameMapping = mapping;
	}

	setCustomPropertyNameMapping( mapping ) {
		customPropertyMapping = mapping;
	}

	_parse(Uint8List data ) {

		Map<String,dynamic> parseHeader(String data, [headerLength = 0 ]) {
			final patternHeader = RegExp(r'/^ply([\s\S]*)end_header(\r\n|\r|\n)/');
			String headerText = '';
			final result = data.split(patternHeader);//patternHeader.exec( data );

			if ( result.isNotEmpty ) {
				headerText = result[ 1 ];
			}

			final header = {
				'comments': [],
				'elements': [],
				'headerLength': headerLength,
				'objInfo': ''
			};

			final lines = headerText.split( RegExp(r'/\r\n|\r|\n/') );
			Map<String,dynamic>? currentElement;

			Map<String, dynamic> make_ply_element_property( propertValues, propertyNameMapping ) {
				final property = { 'type': propertValues[ 0 ] };

				if ( property['type'] == 'list' ) {
					property['name'] = propertValues[ 3 ];
					property['countType'] = propertValues[ 1 ];
					property['itemType'] = propertValues[ 2 ];
				} 
        else {
					property['name'] = propertValues[ 1 ];
				}

				if (this.propertyNameMapping.containsKey(property['name']) ) {
					property['name'] = propertyNameMapping[ property['name'] ];
				}

				return property;
			}

			for (int i = 0; i < lines.length; i ++ ) {
				String line = lines[ i ];
				line = line.trim();

				if ( line == '' ) continue;

				final lineValues = line.split(RegExp(r'/\s+/'));
				final lineType = lineValues.removeAt(0);
				line = lineValues.join( ' ' );

				switch ( lineType ) {
					case 'format':
						header['format'] = lineValues[ 0 ];
						header['version'] = lineValues[ 1 ];
						break;
					case 'comment':
						header['comments'].add( line );
						break;
					case 'element':
						if ( currentElement != null ) {
							header['elements'].add( currentElement );
						}

						currentElement = {};
						currentElement['name'] = lineValues[ 0 ];
						currentElement['count'] = int.parse( lineValues[ 1 ] );
						currentElement['properties'] = [];

						break;
					case 'property':
						currentElement?['properties'].add( make_ply_element_property( lineValues, propertyNameMapping ) );
						break;
					case 'obj_info':
						header['objInfo'] = line;
						break;
					default:
						console.info('unhandled $lineType $lineValues');
				}
			}

			if ( currentElement != null ) {
				header['elements'].add( currentElement );
			}

			return header;
		}

		num? parseASCIINumber( n, type ) {
			switch ( type ) {
				case 'char': case 'uchar': case 'short': case 'ushort': case 'int': case 'uint':
				case 'int8': case 'uint8': case 'int16': case 'uint16': case 'int32': case 'uint32':
					return int.parse( n );
				case 'float': case 'double': case 'float32': case 'float64':
					return double.parse( n );
			}
      return null;
		}

		Map<String, dynamic>? parseASCIIElement( properties, tokens ) {
			Map<String, dynamic> element = {};

			for (int i = 0; i < properties.length; i ++ ) {
				if ( tokens.empty() ) return null;
				if (properties[ i ] is List) {
					final list = [];
					final n = parseASCIINumber( tokens.next(), properties[ i ].countType ) ?? 0;

					for (int j = 0; j < n; j ++ ) {
						if ( tokens.empty() ) return null;
						list.add( parseASCIINumber( tokens.next(), properties[ i ].itemType ) );
					}

					element[ properties[ i ].name ] = list;
				} else {
					element[ properties[ i ].name ] = parseASCIINumber( tokens.next(), properties[ i ].type );
				}
			}

			return element;
		}

		Map<String, dynamic> createBuffer() {
			final Map<String, dynamic> buffer = {
			  'indices': [],
			  'vertices': [],
			  'normals': [],
			  'uvs': [],
			  'faceVertexUvs': [],
			  'colors': [],
			  'faceVertexColors': []
			};

			for (final customProperty in customPropertyMapping.keys) {
			  buffer[ customProperty ] = [];
			}

			return buffer;
		}

		Map<String, dynamic> mapElementAttributes(Map<String,dynamic> properties ) {
			// final String elementNames = properties.map( property => {
			// 	return property.name;
			// });

			String? findAttrName( names ) {
				for (int i = 0, l = names.length; i < l; i ++ ) {
					final name = names[ i ];
					if ( properties.containsKey(name) ) return name;//.contains( name )
				}

				return null;
			}

			return {
				'attrX': findAttrName( [ 'x', 'px', 'posx' ] ) ?? 'x',
				'attrY': findAttrName( [ 'y', 'py', 'posy' ] ) ?? 'y',
				'attrZ': findAttrName( [ 'z', 'pz', 'posz' ] ) ?? 'z',
				'attrNX': findAttrName( [ 'nx', 'normalx' ] ),
				'attrNY': findAttrName( [ 'ny', 'normaly' ] ),
				'attrNZ': findAttrName( [ 'nz', 'normalz' ] ),
				'attrS': findAttrName( [ 's', 'u', 'texture_u', 'tx' ] ),
				'attrT': findAttrName( [ 't', 'v', 'texture_v', 'ty' ] ),
				'attrR': findAttrName( [ 'red', 'diffuse_red', 'r', 'diffuse_r' ] ),
				'attrG': findAttrName( [ 'green', 'diffuse_green', 'g', 'diffuse_g' ] ),
				'attrB': findAttrName( [ 'blue', 'diffuse_blue', 'b', 'diffuse_b' ] ),
			};
		}

		BufferGeometry postProcess(Map<String,dynamic> buffer ) {
			BufferGeometry geometry = BufferGeometry();

			// mandatory buffer data

			if ( buffer['indices'].length > 0 ) {
				geometry.setIndex( buffer['indices'] );
			}

			geometry.setAttributeFromString( 'position', Float32BufferAttribute.fromList( buffer['vertices'], 3 ) );

			// optional buffer data

			if ( buffer['normals'].length > 0 ) {
				geometry.setAttributeFromString( 'normal', Float32BufferAttribute.fromList( buffer['normals'], 3 ) );
			}

			if ( buffer['uvs'].length > 0 ) {
				geometry.setAttributeFromString( 'uv', Float32BufferAttribute.fromList( buffer['uvs'], 2 ) );
			}

			if ( buffer['colors'].length > 0 ) {
				geometry.setAttributeFromString( 'color', Float32BufferAttribute.fromList( buffer['colors'], 3 ) );
			}

			if ( buffer['faceVertexUvs'].length > 0 || buffer['faceVertexColors'].length > 0 ) {
				geometry = geometry.toNonIndexed();

				if ( buffer['faceVertexUvs'].length > 0 ) geometry.setAttributeFromString( 'uv', Float32BufferAttribute.fromList( buffer['faceVertexUvs'], 2 ) );
				if ( buffer['faceVertexColors'].length > 0 ) geometry.setAttributeFromString( 'color', Float32BufferAttribute.fromList( buffer['faceVertexColors'], 3 ) );
			}

			// custom buffer data

			for (final customProperty in customPropertyMapping.keys) {
				if ( buffer[ customProperty ].length > 0 ) {
				  	geometry.setAttributeFromString(
						customProperty,
					  Float32BufferAttribute.fromList(
              buffer[ customProperty ],
              customPropertyMapping[ customProperty ].length
						)
				  );
				}
			}

			geometry.computeBoundingSphere();

			return geometry;
		}

		void handleElement(Map<String,dynamic> buffer, elementName, element, Map<String,dynamic> cacheEntry ) {
			if ( elementName == 'vertex' ) {
				buffer['vertices'].add( element[ cacheEntry['attrX'] ], element[ cacheEntry['attrY'] ], element[ cacheEntry['attrZ'] ] );

				if ( cacheEntry['attrNX'] != null && cacheEntry['attrNY'] != null && cacheEntry['attrNZ'] != null ) {
					buffer['normals'].add( element[ cacheEntry['attrNX'] ], element[ cacheEntry['attrNY'] ], element[ cacheEntry['attrNZ'] ] );
				}

				if ( cacheEntry['attrS'] != null && cacheEntry['attrT'] != null ) {
					buffer['uvs'].add( element[ cacheEntry['attrS'] ], element[ cacheEntry['attrT'] ] );
				}

				if ( cacheEntry['attrR'] != null && cacheEntry['attrG'] != null && cacheEntry['attrB'] != null ) {
					_color.setRGB(
						element[ cacheEntry['attrR'] ] / 255.0,
						element[ cacheEntry['attrG'] ] / 255.0,
						element[ cacheEntry['attrB'] ] / 255.0
					).convertSRGBToLinear();

					buffer['colors'].add( _color.red, _color.green, _color.blue );
				}

				for (final customProperty in customPropertyMapping.keys) {
					for (final elementProperty in customPropertyMapping[ customProperty ] ) {
					  buffer[ customProperty ].add( element[ elementProperty ] );
					}
				}
			} 
      else if ( elementName == 'face' ) {
				final vertex_indices = element['vertex_indices'] ?? element['vertex_index']; // issue #9338
				final texcoord = element['texcoord'];

				if ( vertex_indices.length == 3 ) {
					buffer['indices'].add( vertex_indices[ 0 ], vertex_indices[ 1 ], vertex_indices[ 2 ] );

					if ( texcoord && texcoord.length == 6 ) {
						buffer['faceVertexUvs'].add( texcoord[ 0 ], texcoord[ 1 ] );
						buffer['faceVertexUvs'].add( texcoord[ 2 ], texcoord[ 3 ] );
						buffer['faceVertexUvs'].add( texcoord[ 4 ], texcoord[ 5 ] );
					}
				} 
        else if ( vertex_indices.length == 4 ) {
					buffer['indices'].add( vertex_indices[ 0 ], vertex_indices[ 1 ], vertex_indices[ 3 ] );
					buffer['indices'].add( vertex_indices[ 1 ], vertex_indices[ 2 ], vertex_indices[ 3 ] );
				}

				// face colors

				if ( cacheEntry['attrR'] != null && cacheEntry['attrG'] != null && cacheEntry['attrB'] != null ) {
					_color.setRGB(
						element[ cacheEntry['attrR'] ] / 255.0,
						element[ cacheEntry['attrG'] ] / 255.0,
						element[ cacheEntry['attrB'] ] / 255.0
					).convertSRGBToLinear();
					buffer['faceVertexColors'].add( _color.red, _color.green, _color.blue );
					buffer['faceVertexColors'].add( _color.red, _color.green, _color.blue );
					buffer['faceVertexColors'].add( _color.red, _color.green, _color.blue );
				}
			}
		}

		BufferGeometry parseASCII( data, header ) {
			final buffer = createBuffer();

			final patternBody = RegExp(r'/end_header\s+(\S[\s\S]*\S|\S)\s*$/');
			List<String> body = [];
      String matches = data.split( patternBody );

			if (matches.isNotEmpty) {
				body = matches[1].split(r'/\s+/');
			} 

			final tokens = ArrayStream( body );

			loop: for (int i = 0; i < header.elements.length; i ++ ) {
				final elementDesc = header.elements[ i ];
				final attributeMap = mapElementAttributes( elementDesc.properties );

				for (int j = 0; j < elementDesc.count; j ++ ) {
					final element = parseASCIIElement( elementDesc.properties, tokens );
					if (element == null) break loop;
					handleElement( buffer, elementDesc.name, element, attributeMap );
				}
			}

			return postProcess( buffer );
		}

		List binaryReadElement( at, properties ) {
			final element = {};
			int read = 0;

			for ( int i = 0; i < properties.length; i ++ ) {
				final property = properties[ i ];
				final valueReader = property['valueReader'];

				if ( property['type'] == 'list' ) {
					final list = [];

					final n = property['countReader'].read( at + read );
					read += property['countReader'].size as int;

					for ( int j = 0; j < n; j ++ ) {
						list.add( valueReader.read( at + read ) );
						read += valueReader.size as int;
					}

					element[ property['name'] ] = list;
				} 
        else {
					element[ property['name'] ] = valueReader.read( at + read );
					read += valueReader.size as int;
				}
			}

			return [ element, read ];
		}

		void setPropertyBinaryReaders(Map<String,dynamic> properties, ByteData body, Endian littleEndian ) {
			Map<String,dynamic>? getBinaryReader(ByteData dataview, String type, Endian littleEndian ) {
				switch ( type ) {
					// corespondences for non-specific length types here match rply:
					case 'int8':	case 'char':	return { 'read': ( at ){
						return dataview.getInt8( at );
					}, 'size': 1 };
					case 'uint8':	case 'uchar':	return { 'read': ( at ){
						return dataview.getUint8( at );
					}, 'size': 1 };
					case 'int16':	case 'short':	return { 'read': ( at ){
						return dataview.getInt16( at, littleEndian );
					}, 'size': 2 };
					case 'uint16':	case 'ushort':	return { 'read': ( at ){
						return dataview.getUint16( at, littleEndian );
					}, 'size': 2 };
					case 'int32':	case 'int':		return { 'read': ( at ){
						return dataview.getInt32( at, littleEndian );
					}, 'size': 4 };
					case 'uint32':	case 'uint':	return { 'read': ( at ){
						return dataview.getUint32( at, littleEndian );
					}, 'size': 4 };
					case 'float32': case 'float':	return { 'read': ( at ){
						return dataview.getFloat32( at, littleEndian );
					}, 'size': 4 };
					case 'float64': case 'double':	return { 'read': ( at ){
						return dataview.getFloat64( at, littleEndian );
					}, 'size': 8 };
				}

        return null;
			}

			for (int i = 0, l = properties.length; i < l; i ++ ) {
				final property = properties[ i ];

				if ( property['type'] == 'list' ) {
					property['countReader'] = getBinaryReader( body, property['countType'], littleEndian );
					property['valueReader'] = getBinaryReader( body, property['itemType'], littleEndian );
				} 
        else {
					property['valueReader'] = getBinaryReader( body, property['type'], littleEndian );
				}
			}
		}

		BufferGeometry parseBinary(ByteData data, header ) {
			final buffer = createBuffer();

			final littleEndian = ( header['format'] == 'binary_little_endian' )?Endian.little:Endian.big;
			final body = data.buffer.asUint8List().sublist(0,header['headerLength']).buffer.asByteData();//DataView( data, header['headerLength'] );
			List result;
      int loc = 0;

			for (int currentElement = 0; currentElement < header['elements'].length; currentElement ++ ) {
				final elementDesc = header.elements[ currentElement ];
				final properties = elementDesc.properties;
				final attributeMap = mapElementAttributes( properties );

				setPropertyBinaryReaders( properties, body, littleEndian );

				for (int currentElementCount = 0; currentElementCount < elementDesc.count; currentElementCount ++ ) {
					result = binaryReadElement( loc, properties );
					loc += result[ 1 ] as int;
					final element = result[ 0 ];

					handleElement( buffer, elementDesc.name, element, attributeMap );
				}
			}

			return postProcess( buffer );
		}

		Map<String,dynamic> extractHeaderText(Uint8List bytes ) {
			int i = 0;
			bool cont = true;

			String line = '';
			List<String> lines = [];

			final startLine = String.fromCharCodes(bytes.sublist( 0, 5 ));
			final hasCRNL = r'/^ply\r\n/'.contains( startLine );

			do {
				final c = String.fromCharCode( bytes[ i ++ ] );

				if ( c != '\n' && c != '\r' ) {
					line += c;
				} 
        else {
					if ( line == 'end_header' ) cont = false;
					if ( line != '' ) {
						lines.add( line );
						line = '';
					}
				}
			} while ( cont && i < bytes.length );

			// ascii section using \r\n as line endings
			if ( hasCRNL == true ) i++;
			return { 
        'headerText': '${lines.join('\r')}\r', 
        'headerLength': i 
      };
		}

		BufferGeometry geometry;
		//if ( data is NativeArray ) {
			final bytes = data.sublist(0);
      final temp = extractHeaderText( bytes );
			final headerText = temp['headerText'];
      final headerLength = temp['headerLength'];
			final header = parseHeader( headerText, headerLength );
 
			if ( header['format'] == 'ascii' ) {
				final text = String.fromCharCodes(bytes);
				geometry = parseASCII( text, header );
			} 
      else {
				geometry = parseBinary( data.buffer.asByteData(), header );
			}
		// } 
    // else {
		// 	geometry = parseASCII( data, parseHeader( data ) );
		// }

		return geometry;
	}
}

class ArrayStream {
  dynamic arr;
  int i = 0;
	ArrayStream(this.arr );

	empty() {
		return i >= arr.length;
	}

	next() {
		return arr[i ++];
	}
}