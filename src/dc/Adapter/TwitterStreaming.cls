/// Inspired on https://github.com/intersystems-community/irisdemo-demo-twittersentiment by https://github.com/amirsamary
Class dc.Adapter.TwitterStreaming Extends Ens.InboundAdapter
{

Parameter TwitterAPIServer = "stream.twitter.com";

Parameter TwitterAPIVersion = 1.1;

Parameter TwitterAPIMethod = "statuses/filter";

Parameter TwitterUserAgent = "IRIS Twitter Streaming Demo Adapter 1.0";

Parameter SSLCONFIG = "Twitter";

Property Timeout As %Integer [ InitialExpression = 5 ];

Property TwitterAppConsumerCredentials As %String [ InitialExpression = "None" ];

Property TwitterAppConsumerCredentialsObj As Ens.Config.Credentials;

Property TwitterAccessTokenCredentials As %String [ InitialExpression = "None" ];

Property TwitterAccessTokenCredentialsObj As Ens.Config.Credentials;

Property TwitterAPITrackString As %String(MAXLEN = "");

Property TwitterAPIFollowString As %String(MAXLEN = "");

Property TwitterAPILanguageString As %String(MAXLEN = "") [ InitialExpression = "en" ];

Property TwitterConsumerKey As dc.OAuth1.ConsumerKey;

Property TwitterAccessToken As dc.OAuth1.AccessToken;

Property TwitterStreamingHasStarted As %Boolean [ InitialExpression = 0 ];

Property TwitterStreamingRequest As dc.Adapter.API.StreamingRequest;

Property TwitterStreamingConnection As dc.Adapter.API.StreamingConnection;

Property TweetsPerCallInterval As %Integer [ InitialExpression = 2 ];

Property ConnectionAttempts As %Integer [ Private ];

Property FailureTimeout As %Integer [ InitialExpression = 300 ];

Property SentLimitAlert As %Boolean [ Private ];

Parameter SETTINGS = "TweetsPerCallInterval,TwitterAPITrackString,TwitterAPILanguageString,TwitterAppConsumerCredentials:Basic:credentialsSelector,TwitterAccessTokenCredentials:Basic:credentialsSelector";

Method OnInit() As %Status
{
		Set tSC = $$$OK
		Try
		{
			Kill ^twitter.debug

			//$$$TRACE("Validating Twitter Credentials")
			Set tSC = ..ValidateCredentials()
			Quit:$$$ISERR(tSC)

			Set ..TwitterConsumerKey = ##class(dc.OAuth1.ConsumerKey).%New(..TwitterAppConsumerCredentialsObj)
			Set ..TwitterAccessToken = ##class(dc.OAuth1.AccessToken).%New(..TwitterAccessTokenCredentialsObj)

			Set tSC = ..ValidateParameters()
			Quit:$$$ISERR(tSC)

			Set tSC=##super()
			Quit:$$$ISERR(tSC)
		}
		Catch (oException)
		{
			Set tSC = oException.AsStatus()
		}

		Quit tSC
}

Method ValidateCredentials()
{
		Set tSC = $$$OK
		Try
		{
			If ..TwitterAppConsumerCredentials=""
			{
				Set tSC = $$$ERROR(5001,"You must configure your Twitter's Application Consumer Credentials (Twitter Application's Consumer Key and Consumer Secret).")
				Quit
			}

			If '$IsObject(..TwitterAppConsumerCredentialsObj)
			{
				Do ..TwitterCredentialsObjSet("TwitterAppConsumerCredentials", ..TwitterAppConsumerCredentials)
				If '$IsObject(..TwitterAppConsumerCredentialsObj)
				{
					Set tSC=$$$EnsError($$$EnsErrNoCredentials,..TwitterAppConsumerCredentials)
					Quit
				}

				If (..TwitterAppConsumerCredentialsObj.Username="") || (..TwitterAppConsumerCredentialsObj.Password="")
				{
					Set tSC = $$$ERROR(5001,"Twitter Application's Consumer Credential must have a username (consumer key) and a password (consumer secret).")
					Quit
				}
			}

			If ..TwitterAccessTokenCredentials=""
			{
				Set tSC = $$$ERROR(5001,"You must configure your Twitter's Application Access Token Credentials (Twitter Application's Access Token and Access Token Secret).")
				Quit
			}

			If '$IsObject(..TwitterAccessTokenCredentialsObj)
			{
				Do ..TwitterCredentialsObjSet("TwitterAccessTokenCredentials", ..TwitterAccessTokenCredentials)
				If '$IsObject(..TwitterAccessTokenCredentialsObj)
				{
					Set tSC=$$$EnsError($$$EnsErrNoCredentials,..TwitterAccessTokenCredentials)
					Quit
				}

				If (..TwitterAccessTokenCredentialsObj.Username="") || (..TwitterAccessTokenCredentialsObj.Password="")
				{
					Set tSC = $$$ERROR(5001,"Twitter Application's Access Token Credential must have a username (Access Token) and a password (Access Token Secret).")
					Quit
				}
			}
		}
		Catch (oException)
		{
			Set tSC = oException.AsStatus()
		}

		Quit tSC
}

Method ValidateParameters()
{
		Set tSC = $$$OK
		Try
		{
			Set ..TwitterAPILanguageString=$ZStrip(..TwitterAPILanguageString,"<>W")
			Set ..TwitterAPIFollowString=$ZStrip(..TwitterAPIFollowString,"<>W")
			Set ..TwitterAPITrackString=$ZStrip(..TwitterAPITrackString,"<>W")

			If (..TwitterAPIFollowString="") && (..TwitterAPITrackString="")
			{
				Set tSC = $$$ERROR(5001,"You must configure either TwitterAPIFollowString (follow) or TwitterAPITrackString (track) parameter.")
				Quit
			}
		}
		Catch (oException)
		{
			Set tSC = oException.AsStatus()
		}

		Quit tSC
}

Method TwitterCredentialsObjSet(pCredentialsPropertyName As %String, pInVal As %String) As %Status
{
		Set tCredentialObjPropName = pCredentialsPropertyName_"Obj"
		Set $property($this, tCredentialObjPropName)=$$$NULLOREF

		Set tClassname=$zobjmethod($this,"%ClassName",1) ; call subclass
		Set tClass = $$$comMemberKeyGet(tClassname,$$$cCLASSproperty,tCredentialObjPropName,$$$cPROPtype)
		If ""'=tClass {
			Set tSC=##Class(Ens.Config.Credentials).GetCredentialsObj(.tObj,tClassname,tClass,pInVal)
			If $$$ISOK(tSC) { Set $property($this, tCredentialObjPropName)=tObj }
			ElseIf '$$$StatusEquals(tSC,$$$EnsErrNoCallerCredentials) {
				$$$LOGSTATUS(tSC)
			}
		}

		Quit $$$OK
}

Method OnTask() As %Status
{
		Set tSC=$$$OK
		Try
		{
			If ..TwitterStreamingConnection.StreamingStarted
			{
				Do ..ProcessNextMessage()
			}
			Else
			{
				Do ..StartStreaming()
			}
		}
		Catch (oException)
		{
			If oException.Name'="ProcessInputException"
			{
				Set tSC = oException.AsStatus()
				Do ..Debug("OnTask: "_$System.Status.GetErrorText(tSC))

				If $IsObject(..TwitterStreamingConnection)
				{
					Do ..TwitterStreamingConnection.Disconnect()

					Do ..ComputeBackoffPatternWait()

					Do ..Debug("Disconnected because of error. Next reconnect attempt will be in "_..CallInterval_" seconds.")
				}
			}
		}

		Quit tSC
}

Method ProcessNextMessage()
{
		For i=1:1:..TweetsPerCallInterval
		{
			Set json=""

			Do ..TwitterStreamingConnection.GetMessage(.json)

			Continue:json=""

			Try
			{
				Set message = ##class(%Library.DynamicObject).%FromJSON(json)
			}
			Catch
			{
				Do ..SendAlert("Got a non JSON error message: "_json)
				Quit
			}

			If message.%IsDefined("text")
			{
				Set pInput = ##class(dc.BS.Tweet).CreateFromJSON(message)

				Set tSC = ..BusinessHost.ProcessInput(pInput, .pOutputIgnored)
				Throw:$$$ISERR(tSC) tSC
			}
			ElseIf message.%IsDefined("limit")
			{
				If '..SentLimitAlert
				{
					Do ..SendAlert("Limit System Message Received: Your filters have matched more Tweets than its current rate limit allows to be delivered.")
					Set ..SentLimitAlert=1
				}
			}
			Else
			{
				Do ..SendAlertWithSystemMessage(message)
			}
		}
}

Method SendAlertWithSystemMessage(pSystemMessageJSONObj As %Library.DynamicObject)
{
		Set alert=##class(Ens.AlertRequest).%New()
		If pSystemMessageJSONObj.%GetIterator().%GetNext(.messageType, .message)
		{
			Set alert.AlertText="Twitter system message of type "_messageType_": "_message.%ToJSON()
		}
		Else
		{
			Set alert.AlertText="Unknown message format received from twitter:"_pSystemMessageJSONObj.%ToJSON()
		}
		Do ..BusinessHost.SendAlert(alert)
}

Method SendAlert(pMessage As %String)
{
		Set alert=##class(Ens.AlertRequest).%New()
		Set alert.AlertText=pMessage
		Do ..BusinessHost.SendAlert(alert)
}

Method StartStreaming() As %Status
{
		#Dim doSignedData As %Library.DynamicObject

		//$$$TRACE("Start streaming...")
		// STREAMING REQUEST
		Set ..TwitterStreamingRequest = ##class(dc.Adapter.API.StreamingRequest).%New(..TwitterConsumerKey, ..TwitterAccessToken)
		Set ..TwitterStreamingRequest.Follow=..TwitterAPIFollowString
		Set ..TwitterStreamingRequest.Track=..TwitterAPITrackString
		Set ..TwitterStreamingRequest.Language=..TwitterAPILanguageString

		// STREAMING CONNETION
		Set ..TwitterStreamingConnection= ##class(dc.Adapter.API.StreamingConnection).%New(..TwitterStreamingRequest)
		Set ..TwitterStreamingConnection.UserAgent=..#TwitterUserAgent
		Set ..TwitterStreamingConnection.SSLConfiguration="Twitter"

		// START STREAMING - This method can throw an exception
		Do ..TwitterStreamingConnection.StartStreaming()

		Set ..CallInterval=0.1
}

Method ComputeBackoffPatternWait()
{
		Set ..ConnectionAttempts=..ConnectionAttempts+1

		Set ..CallInterval=2**..ConnectionAttempts

		If ..CallInterval>..FailureTimeout
		{
			Set ..CallInterval=..FailureTimeout
		}
}

Method Debug(pMsg)
{
		Set ^twitter.debug($I(^twitter.debug))=pMsg
}

}
