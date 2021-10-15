Class dc.BS.TwitterEntities Extends (%SerialObject, %XML.Adaptor)
{

Property hashtags As list Of %String(MAXLEN = "");

Property urls As list Of %String(MAXLEN = "");

Property "user_mentions" As list Of %String(MAXLEN = "");

Method PopulateFromJSON(pJSON As %Library.DynamicObject)
{
		#Dim iterator As %Iterator.Object

		// hashtags
		Set arIterator = pJSON.hashtags.%GetIterator()

		While arIterator.%GetNext(.arKey, .obj)
		{
			Do ..hashtags.Insert(obj.text)
		}

		// urls
		Set arIterator = pJSON.urls.%GetIterator()

		While arIterator.%GetNext(.arKey, .obj)
		{
			Do ..urls.Insert(obj."expanded_url")
		}

		// user_mentions
		Set arIterator = pJSON."user_mentions".%GetIterator()

		While arIterator.%GetNext(.arKey, .obj)
		{
			Do .."user_mentions".Insert(obj."screen_name")
		}
}

Storage Default
{
<Data name="TwitterEntitiesState">
<Value name="1">
<Value>hashtags</Value>
</Value>
<Value name="2">
<Value>urls</Value>
</Value>
<Value name="3">
<Value>user_mentions</Value>
</Value>
</Data>
<State>TwitterEntitiesState</State>
<StreamLocation>^dc.BS.TwitterEntitiesS</StreamLocation>
<Type>%Storage.Serial</Type>
}

}
