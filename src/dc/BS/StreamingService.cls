/// Inspired on https://github.com/intersystems-community/irisdemo-demo-twittersentiment by https://github.com/amirsamary
Class dc.BS.StreamingService Extends Ens.BusinessService
{

Property TargetConfigName As %String(MAXLEN = 1000);

Parameter ADAPTER = "Twitter.Adapter.StreamingInboundAdapter";

Parameter SETTINGS = "TargetConfigName:Basic:selector?multiSelect=0&context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},-PoolSize";

Method OnProcessInput(pRawSingleTweetStream As dc.BS.Tweet, Output pOutput As %Stream.Object) As %Status
{
		If ..TargetConfigName'=""
		{
			Set tSC = ..SendRequestAsync(..TargetConfigName , pRawSingleTweetStream)
		}
		Else
		{
			Set tSC = $$$ERROR(5001,"TargetConfigName is not configured.")
		}

		Quit tSC
}

ClassMethod OnGetConnections(Output pArray As %String, pItem As Ens.Config.Item)
{
		Do ##super(.pArray,pItem)
		If pItem.GetModifiedSetting("TargetConfigName",.tValue) {
			For i=1:1:$L(tValue,",") { Set tOne=$ZStrip($P(tValue,",",i),"<>W")  Continue:""=tOne  Set pArray(tOne)="" }
		}
}

}
