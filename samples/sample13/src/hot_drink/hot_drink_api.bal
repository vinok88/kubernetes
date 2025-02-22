import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/config;
import ballerinax/jdbc;
import ballerinax/kubernetes;

@kubernetes:Service {
    name: "hotdrink-backend"
}
listener http:Listener hotDrinkEP = new(9090);

 jdbc:Client hotdrinkDB = new({
    url: "jdbc:mysql://hotdrink-mysql.mysql:3306/hotdrinkdb",
    username: config:getAsString("db.username"),
    password: config:getAsString("db.password"),
    poolOptions: { maximumPoolSize: 5 },
    dbOptions: { useSSL: false }
});


@kubernetes:ConfigMap {
    conf: "./hot_drink/ballerina.conf"
}
@kubernetes:Deployment {
    copyFiles: [{ 
        target: "/ballerina/runtime/bre/lib",
        sourceFile: "./resource/lib/mysql-connector-java-8.0.11.jar"
    }]
}
@http:ServiceConfig {
    basePath: "/hotDrink"
}
service HotDrinksAPI on hotDrinkEP {
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/menu"
    }
    resource function gethotdrinkMenu(http:Caller outboundEP, http:Request req) {
        http:Response response = new;

        var selectRet = hotdrinkDB->select("SELECT * FROM hotdrink", HotDrink);
        if (selectRet is table<HotDrink>) {
            var jsonConversionRet = json.convert(selectRet);
            if (jsonConversionRet is json) {
                response.setJsonPayload(<@untainted> jsonConversionRet);
            } else if (jsonConversionRet is error) {
                log:printError("Error in table to json conversion", jsonConversionRet);
                response.setTextPayload("Error in table to json conversion");
            }
        } else if (selectRet is error) {
            log:printError("Retrieving data from hotdrink table failed", selectRet);
            response.setTextPayload("Error in reading results");
        }

        var responseResult = outboundEP->respond(response);
        if (responseResult is error) {
            log:printError("error responding back to client.", responseResult);
        }
    }
}

type HotDrink record {|
    int id;
    string name;
    string description;
    float price;
|};
