#!/usr/bin/php
<?php
/*Nagios Exit codes
		0 = OK
		1 = WARNING
		2 = CRITICAL
		3 = UNKNOWN
 
perfdata output rta=35.657001ms;1000.000000;3000.000000;0.000000 pl=0%;80;100;0
 
*/
 
 
//Set provided variables
$arguements = getopt("H:U:P:s:c:S:u:w:C:t:n:");
 
$secure = isset($arguements['s']) ? $arguements['s'] : 0;
$command = isset($arguements['c']) ? $arguements['c'] : "status";
$stat = isset($arguements['S']) ? $arguements['S'] : "iops";
$uom = isset($arguements['u']) ? $arguements['u'] : "";
$warnType = isset($arguements['t']) ? $arguements['t'] : "greaterthan";
$volumeName = isset($arguements['n']) ? $arguements['n'] : "";
 
if(isset($arguements['w']) || isset($arguements['C'])) {
		if(!isset($arguements['w']) || !isset($arguements['C'])) {
				echo "Specify warning/critical threshold \n\r";
				Usage();
				exit(3);
		}
		else {
				$warning = $arguements['w'];
				$critical = $arguements['C'];
		}
}
 
//Validate Provided arguements
if(!isset($arguements['H']) || !isset($arguements['U']) || !isset($arguements['P'])) {
		Usage();
		exit(3);
}
elseif(($command == 'named-volume') && (empty($volumeName))) {
		Usage();
		exit(3);
}
elseif(($command == 'named-vdisk') && (empty($volumeName))) {
		Usage();
		exit(3);
}
else {
		//Concatenate Username and password into auth string
		$concatAuth = $arguements['U'] . "_" . $arguements['P'];
		$concatMD5 = md5($concatAuth);
		$hostAddr = $arguements['H'];
		$auth = $concatMD5;
		$authstr = "/api/login/".$auth;
}
 
$successful =0;
 
 
//Set up HTTP request depending on whether secure or not.
if($secure) {
		$url = "https://".$hostAddr."/api/";
 
		$ssl_array = array('version' => 3);
		$r = new HttpRequest("$url", HttpRequest::METH_POST, array('ssl' => $ssl_array));
}
else {
		$url = "http://".$hostAddr."/api/";
 
		$r = new HttpRequest("$url", HttpRequest::METH_POST);
}
 
//Send the Authorisation String
$r->setBody("$authstr");
 
 
//Send HTTP Request
try {
	$responce = $r->send()->getBody();
		//echo($responce);
} catch (HttpException $ex) {
		if (isset($ex->innerException)){
				returnNagios("UNKNOWN",$ex->innerException->getMessage());
		}
		else {
				returnNagios("UNKNOWN", $ex->getMessage());
		}
}
 
 
//Check to see if the Authorisation was successful
try {
		$xmlResponse = @new SimpleXMLElement($responce);
}
catch(Exception $e) {
		returnNagios("UNKNOWN", $e->getMessage().". Is this a HP MSA P2000?");
}
 
foreach($xmlResponse->OBJECT->PROPERTY as $Property) {
 
		foreach($Property->attributes() as $name => $val) {
				if($name =="name" && $val =="response-type" && $Property == "success") {
						$successful =1;
				}
		}
}
 
 
//If Auth was successfull continue
if($successful) {
		$sessionVariable =  (string) $xmlResponse->OBJECT->PROPERTY[2];
	   
	   
		switch($command) {
				case "status":
						try {
							   
								//Get Disk Info
								$regXML = getRequest($sessionVariable, "{$url}show/disks", $secure);
								$regXML = new SimpleXMLElement($regXML);
 
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
										//Get HDD Statuses
										if($attr['name']== "drive") {
												$type = "Disks";
												$statuses[$type][]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'health'));
										}
								}
								
								//Get VDisk Info
                                $regXML = getRequest($sessionVariable, "{$url}show/vdisks", $secure);
                                $regXML = new SimpleXMLElement($regXML);

                                foreach($regXML->OBJECT as $obj) {
                                        $attr = $obj->attributes();
                                        //Get Vdisk Statuses
                                        if($attr['name']== "virtual-disk") {
                                                $type = "Vdisk";
                                                $statuses[$type][]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'health'));
                                        }
                                }
							   
 
								//Get Sensor Information
								$regXML = getRequest($sessionVariable, "{$url}show/sensor-status", $secure);
								$regXML = new SimpleXMLElement($regXML);
 
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
										if($attr['name']== "sensor") {
												switch((string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'sensor-type'))) {
														case "3":
																$type = "Temperature";
																break;
														case "9":
																$type = "Voltage";
																break;
														case "2":
																$type = "Overall";
																break;
												}
												$statuses[$type][]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'status'));
										}
								}
 
 
								//Get FRU Information
								$regXML = getRequest($sessionVariable, "{$url}show/frus", $secure);
								$regXML = new SimpleXMLElement($regXML);
 
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
										if($attr['name']== "fru") {
												$type = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'fru-shortname'));
												$statuses[$type][]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'fru-status'));
										}
								}
 
 
								//Get Enclosure Information
								$regXML = getRequest($sessionVariable, "{$url}show/enclosures", $secure);
								$regXML = new SimpleXMLElement($regXML);
 
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
										if($attr['name']== "enclosures") {
												$type = "Enclosures";
												$statuses[$type][]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'health'));
										}
								}
 
	   
					   
								if(count($statuses) < 1) {
										//Use API to run command and get XML
										$regXML = getRequest($sessionVariable, "{$url}show/enclosure-status", $secure);
										$regXML = new SimpleXMLElement($regXML);
			   
					   
										foreach($regXML->OBJECT as $obj) {
												//get statuses of components and enclosures and enter status into array
 
												$attr = $obj->attributes();
												//Get all the enlosure components HDD, FAN, PSU etc
												if($attr['name']== "enclosure-component") {
														$type = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'display-name', 'value'=>'Type'));
														$statuses[$type][]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'status'));
												}
					   
												//Get all overall enclosure status
												if($attr['name'] == "enclosure-environmental") {
														$type = "Enclosure";
														$statuses[$type][]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'status'));                              
												}
										}
								}
							   
								//print_r($statuses);
						}
						catch(Exception $e) {
								returnNagios("UNKNOWN", $e->getMessage());
						}
 
						//loop through statuses array and create the Output. Also get the overall state.
						//Use highest status as overall status.
						//Count each type and produce output.
	   
						if(isset($statuses)) {
								$overallStatus = "OK";
								$output = "";
								foreach($statuses as $typ=>$arrType) {
										$output .= $typ;
										$typeWarn =0;
										$typeOK =0;
										$typeCrit = 0; 
	   
										foreach($arrType as $arrTypeStatus) {
												switch($arrTypeStatus) {
														case "Fault" :
																$typeCrit++;
																break; 
 
														case "Warning" :
																$typeWarn++;
																break;
	   
														case "OK" :
																$typeOK++;
																break;
														default:
																$typeCrit++;
																break;
												}
										}
							   
										if($typeWarn >0 && $typeCrit ==0) {
												$output .= " $typeWarn Warning, ";
												$overallStatus = "WARNING";
										}
										if($typeCrit > 0) {
												$output .= " $typeCrit Critical, ";
												$overallStatus = "CRITICAL";
										}
										if($typeCrit ==0 && $typeWarn ==0) {
												$output .= " $typeOK OK, ";
										}
								}
						}
						else {
								returnNagios("UNKNOWN", "Could Not Read API");
						}
						break;
 				
				case "named-volume":
						try {
								//pass $volumename to the end of URL and use API to run command and get XML
								$regXML = getRequest($sessionVariable, "{$url}show/volumes/".$volumeName, $secure);
								$regXML = new SimpleXMLElement($regXML);
			   
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
											   
										if($attr['name']=="volume") {
												$vdiskName = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'virtual-disk-name'));
												$diskName = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'volume-name'));
												$diskSize = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'size'));
												$statuses = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'health'));
												$reason = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'health-reason'));
												$action = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'health-recommendation'));
										}
								}
						}
						catch(Exception $e) {
								returnNagios("UNKNOWN", $e->getMessage().". Check firmware supports command.");
						}
						//Check the return of status and build the output
						if(isset($statuses)){
							$overallStatus = "OK";
							$output = "";
							if($statuses == "OK") {
								//Health is OK
								$overallstatus = 'OK';
								$output = "Volume " . $diskName . " is " . $statuses . ". Size is: " . $diskSize . " vDisk Name is " . $vdiskName . ".";
							}
							elseif($statuses == "Degraded") {
								//Health is Degraded = Warning
								$overallstatus = 'WARNING';
								$output = "Volume " . $diskName . " is " . $statuses . ". Reason is: " . $reason . ". Recommended action is " . $action . ".";
							}
							elseif($statuses == "Fault") {
								//Health is Fault = Critical
								$overallstatus = 'CRITICAL';
								$output = "Volume " . $diskName . " is " . $statuses . ". Reason is: " . $reason . ". Recommended action is " . $action . ".";
							}
							elseif($statuses == "Unknown") {
								//Health is Unknown
								$overallstatus = 'UNKNOWN';
								$output = "Volume " . $diskName . " is " . $statuses . ". Reason is: " . $reason . ". Recommended action is " . $action . ".";
							}
						} else {
							returnNagios("UNKNOWN", "Could Not Read API");
						}
						break;
 
				case "named-vdisk":
						try {
								//pass $volumename to the end of URL and use API to run command and get XML
								$regXML = getRequest($sessionVariable, "{$url}show/vdisks/".$volumeName, $secure);
								$regXML = new SimpleXMLElement($regXML);
			   
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
											   
										if($attr['name']=="virtual-disk") {
												$diskName = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'name'));
												$diskSize = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'size'));
												$statuses = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'health'));
												$reason = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'health-reason'));
												$action = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'health-recommendation'));
										}
								}
						}
						catch(Exception $e) {
								returnNagios("UNKNOWN", $e->getMessage().". Check firmware supports command.");
						}
						//Check the return of status and build the output
						if(isset($statuses)){
							$overallStatus = "OK";
							$output = "";
							if($statuses == "OK") {
								//Health is OK
								$overallstatus = 'OK';
								$output = "vDisk " . $diskName . " is " . $statuses . ". Size is: " . $diskSize . ".";
							}
							elseif($statuses == "Degraded") {
								//Health is Degraded = Warning
								$overallstatus = 'WARNING';
								$output = "vDisk " . $diskName . " is " . $statuses . ". Reason is: " . $reason . ". Recommended action is " . $action . ".";
							}
							elseif($statuses == "Fault") {
								//Health is Fault = Critical
								$overallstatus = 'CRITICAL';
								$output = "vDisk " . $diskName . " is " . $statuses . ". Reason is: " . $reason . ". Recommended action is " . $action . ".";
							}
							elseif($statuses == "Unknown") {
								//Health is Unknown
								$overallstatus = 'UNKNOWN';
								$output = "vDisk " . $diskName . " is " . $statuses . ". Reason is: " . $reason . ". Recommended action is " . $action . ".";
							}
						} else {
							returnNagios("UNKNOWN", "Could Not Read API");
						}
						break;
				case "disk":
						try {
								//Use API to run command and get XML
								$regXML = getRequest($sessionVariable, "{$url}show/disk-statistics", $secure);
								$regXML = new SimpleXMLElement($regXML);
			   
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
											   
										if($attr['name']=="disk-statistics") {
												$diskName = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'durable-id'));
												$perfstats[$diskName]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>$stat), 1);
										}
								}
						}
						catch(Exception $e) {
								returnNagios("UNKNOWN", $e->getMessage().". Check firmware supports command.");
						}
						break;
 
				case "controller":
						try {
								//Use API to run command and get XML
								$regXML = getRequest($sessionVariable, "{$url}show/controller-statistics", $secure);
								$regXML = new SimpleXMLElement($regXML);
			   
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
											   
										if($attr['name']=="controller-statistics") {
												$controllerName = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'durable-id'));
												$perfstats[$controllerName]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>$stat));
										}
								}
						}
						catch(Exception $e) {
								returnNagios("UNKNOWN", $e->getMessage().". Check firmware supports command.");
						}
						break;
 
				case "vdisk":
						try {
								//Use API to run command and get XML
								$regXML = getRequest($sessionVariable, "{$url}show/vdisk-statistics", $secure);
								$regXML = new SimpleXMLElement($regXML);
			   
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
											   
										if($attr['name']=="vdisk-statistics") {
												$vdiskName = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'name'));
												$perfstats[$vdiskName]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>$stat));
										}
								}
						}
						catch(Exception $e) {
								returnNagios("UNKNOWN", $e->getMessage().". Check firmware supports command.");
						}
						break;
 
				case "volume":
						try {
								//Use API to run command and get XML
								$regXML = getRequest($sessionVariable, "{$url}show/volume-statistics", $secure);
								$regXML = new SimpleXMLElement($regXML);
			   
								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
											   
										if($attr['name']=="volume-statistics") {
												$volumeName = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'volume-name'));
												$perfstats[$volumeName]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>$stat));
										}
								}
						}
						catch(Exception $e) {
								returnNagios("UNKNOWN", $e->getMessage().". Check firmware supports command.");
						}
						break;
				case "vdisk-read-latency":
						$stat = "avg-read-rsp-time";
						try {
								//Use API to run command and get XML
								$regXML = getRequest($sessionVariable, "{$url}show/vdisk-statistics", $secure);
								$regXML = new SimpleXMLElement($regXML);

								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
										#print_r($obj);
										if($attr['name']=="vdisk-statistics") {
												$vdiskName = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'name'));
												$perfstats[$vdiskName]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>$stat));
										}
								}
						}
						catch(Exception $e) {
								returnNagios("UNKNOWN", $e->getMessage().". Check firmware supports command.");
						}
						break;

				case "vdisk-write-latency":
						$stat = "avg-write-rsp-time";
						try {
								//Use API to run command and get XML
								$regXML = getRequest($sessionVariable, "{$url}show/vdisk-statistics", $secure);
								$regXML = new SimpleXMLElement($regXML);

								foreach($regXML->OBJECT as $obj) {
										$attr = $obj->attributes();
										#print_r($obj);
										if($attr['name']=="vdisk-statistics") {
												$vdiskName = (string) getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>'name'));
												$perfstats[$vdiskName]= getEnclosureStatus($obj->PROPERTY, array('name'=>'name', 'value'=>$stat));
										}
								}
						}
						catch(Exception $e) {
							returnNagios("UNKNOWN", $e->getMessage().". Check firmware supports command.");
						}
						break;

				default :
						echo "Unknown command specified";
						Usage();
						exit(3);
						break;
		}              
 
		$nonPerfCommands = array('status', 'named-volume', 'named-vdisk');
		if(!in_array($command,$nonPerfCommands)) {
				if(isset($warning) && isset($critical)) {
						$perfOutput = parsePerfData($perfstats, $uom,  $warnType, $warning, $critical);
						$overallStatus = $perfOutput[1];
						$output = "{$command} {$stat} - ".$perfOutput[0];
				}
				else {
						$perfOutput = parsePerfData($perfstats, $uom);
						$output = "{$command} {$stat} - ";
						$output .= $perfOutput;
						$overallStatus = "OK";
				}
		}
 
		returnNagios($overallStatus, $output);
 
}
else {
		//if Auth is unsucessful return Status UKNOWN
		returnNagios("UNKNOWN", "Authentication Unsuccessful");
}
 
function parsePerfData($perfData, $uom="", $warnType=false, $warning=0, $critical=0) {
		$output ="";
		$perfOutput ="";
		$overallState = "OK";
 
		foreach($perfData as $key => $val) {
				$perfOutput .= " {$key}={$val}{$uom};";        
				if($warnType != false) {
						switch($warnType) {
								case "lessthan":
										if($val < $warning && $val > $critical) {
												$overallState = "WARNING";
												$output .= "WARNING ";         
										}
										if($val < $critical) {
												$overallState = "CRITICAL";
												$output .= "CRITICAL ";
										}
										break;
 
								case "greaterthan":
										if($val > $warning && $val < $critical) {
												$overallState = "WARNING";
												$output .= "WARNING ";         
										}
										if($val > $critical) {
												$overallState = "CRITICAL";
												$output .= "CRITICAL ";
										}
											   
										break;
						}
 
						$perfOutput .=$warning.";".$critical."; ";
				}
				else {
						$perfOutput .= ";; ";
				}
				$output .= " {$key} {$val}{$uom}, ";
		}
		$output = $output."|".$perfOutput;
	   
		if($warnType != false) {
				$arrReturn = array($output, $overallState);
				return $arrReturn;
		}
		else {
				return $output;
		}
}
 
function getEnclosureStatus($encXML, $propertyName) {
 
		//Loop through all Property Values in the Object and match values passed in with array key value pair
		foreach($encXML as $prop) {
				$attr = $prop->attributes();
				if($attr[$propertyName['name']] == $propertyName['value']) {
						$status = (string)$prop;
				}
		}
	   
		if(!isset($status)) {
				throw new Exception('No Value Found'); 
		}
 
		return $status;
}
 
function getRequest($sessionKey, $reqUrl, $secure) {
	   
		//Send HTTP request to API and return response
 
		if($secure) {
				$ssl_array = array('version' => 3);
				$r = new HttpRequest("$reqUrl", HttpRequest::METH_GET, array('ssl' => $ssl_array));
		}
		else {
				$r = new HttpRequest("$reqUrl", HttpRequest::METH_GET);
		}
 
		$r->setOptions(array('cookies'=>array('wbisessionkey'=>$sessionKey, 'wbiusername'=>'')));
		$r->setBody();
 
		try {
				$responce = $r->send()->getBody();
				return $responce;
		} catch (HttpException $ex) {
				throw($ex);
		}
}
 
function Usage() {
		//echo usage for the script
 
		echo "
This script sends HTTP Requests to the specified HP P2000 Array to determine its health
and outputs performance data fo other checks.
Required Variables:
		-H Hostname or IP Address
		-U Username
		-P Password
			   
Optional Variables:
		These options are not required. Both critical and warning must be specified together
		If warning/critical is specified -t must be specified or it defaults to greaterthan.                           
		-s Set to 1 for Secure HTTPS Connection
		-c Sets what you want to do
				status - get the status of the SAN
				disk - Get performance data of the disks
				controller - Get performance data of the controllers
				named-volume - Get the staus of an individual volume - MUST have -n volumename specified
				named-vdisk - Get the staus of an individual vdisk - MUST have -n volumename specified
				vdisk - Get performance data of the VDisks
				volume - Get performance data of the volumes
				vdisk-write-latency - Get vdisk write latency (only available in later firmwares)
				vdisk-read-latency - Get vdisk read latency (only available in later firmwares)
		-S specify the stats to get for performance data. ONLY works when -c is specified
		-u Units of measure. What should be appended to performance values. ONLY used when -c specified.
		-w Specify Warning value
		-C Specify Critical value
		-t Specify how critical warning is calculated (DEFAULT greaterthan)
				lessthan - if value is lessthan warning/critical return warning/critical
				greaterthan - if value is greaterthan warning/critical return warning/critical
		-n Volume Name to be used with -c named-volume or -c named-vdisk
	   
Examples
		Just get the status of the P2000
		./check_p2000_api.php -H 192.168.0.2 -U manage -P !manage
		Get the status of the volume name volume1 on the P2000
		./check_p2000_api.php -H 192.168.0.2 -U manage -P !manage -c named-volume -n volume1
 
		Get the CPU load of the controllers and append % to the output
		./check_p2000_api.php -H 192.168.0.2 -U manage -P !manage -s 1 -c controller -S cpu-load -u \"%\"
 
		Get the CPU load of the controllers and append % to the output warning if its over 30 or critical if its over 60
		./check_p2000_api.php -H 192.168.0.2 -U manage -P !manage -s 1 -c controller -S cpu-load -u \"%\" -w 30 -C 60
 
Setting option -c to anything other than status will output performance data for Nagios to process.
You can find certain stat options to use by logging into SAN Manager through the web interface and
manually running the commands in the API. Some options are iops, bytes-per-second-numeric, cpu-load,
write-cache-percent and others. If using Warning/Critical options specify a stat without any Units
otherwise false states will be returned. You can specify units yourself using -u option.
 
";
}
 
function returnNagios($Result="UNKNOWN", $message="") {
		//Return to nagios with appropriate exit code
 
		switch($Result) {
				case "OK":
						echo "OK : ".$message;
						exit(0);
				case "WARNING":
						echo "WARNING : ".$message;
						exit(1);
				case "CRITICAL":
						echo "CRITICAL : ".$message;
						exit(2);
				case "UNKNOWN":
						echo "UNKNOWN: ".$message;
						exit(3);
		}
}
 
?>

