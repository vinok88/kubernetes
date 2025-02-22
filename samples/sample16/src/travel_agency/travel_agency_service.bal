import ballerina/http;
import ballerina/internal;
import ballerina/log;
import ballerinax/kubernetes;
import ballerinax/istio;

@kubernetes:Service {}
@istio:Gateway {}
@istio:VirtualService {}
listener http:Listener travelAgencyEP = new(9090);

http:Client airlineReservationEP = new("http://airline-reservation:8080/airline");
http:Client hotelReservationEP = new("http://hotel-reservation:7070/hotel");
http:Client carRentalEP = new("http://car-rental:6060/car");

// Travel agency service to arrange a complete tour for a user
@kubernetes:Deployment {}
@http:ServiceConfig {
    basePath: "/travel"
}
service travelAgencyService on travelAgencyEP {
    // Resource to arrange a tour
    @http:ResourceConfig {
        methods: ["POST"],
        consumes: ["application/json"],
        produces: ["application/json"],
        path: "/arrange"
    }
    resource function arrangeTour(http:Caller caller, http:Request inRequest) returns error? {
        http:Response outResponse = new;
        json inReqPayload = {};

        // Try parsing the JSON payload from the user request
        var payload = inRequest.getJsonPayload();
        if (payload is json) {
            // Valid JSON payload
            inReqPayload = payload;
        } else {
            // NOT a valid JSON payload
            outResponse.statusCode = 400;
            outResponse.setJsonPayload({
                Message: "Invalid payload - Not a valid JSON payload"
            });
            var result = caller->respond(outResponse);
            handleError(result);
            return;
        }

        json|error inReqPayloadNameJson = inReqPayload.Name;
        json|error inReqPayloadArrivalDateJson = inReqPayload.ArrivalDate;
        json|error inReqPayloadDepartureDateJson = inReqPayload.DepartureDate;
        json|error airlinePreference = inReqPayload.Preference.Airline;
        json|error hotelPreference = inReqPayload.Preference.Accommodation;
        json|error carPreference = inReqPayload.Preference.Car;

        // If payload parsing fails, send a "Bad Request" message as the response
        if (inReqPayloadNameJson is error || inReqPayloadArrivalDateJson is error ||
            inReqPayloadDepartureDateJson is error || airlinePreference is error || hotelPreference is error ||
            carPreference is error) {
            outResponse.statusCode = 400;
            outResponse.setJsonPayload({
                Message: "Bad Request - Invalid Payload"
            });
            var result = caller->respond(outResponse);
            handleError(result);
            return;
        }

        // Reserve airline ticket for the user by calling Airline reservation service
        // construct the payload
        json outReqPayloadAirline = {
            Name: checkpanic inReqPayloadNameJson,
            ArrivalDate: checkpanic inReqPayloadArrivalDateJson,
            DepartureDate: checkpanic inReqPayloadDepartureDateJson,
            Preference: checkpanic airlinePreference
        };

        // Send a post request to airlineReservationService with appropriate payload and get response
        http:Response inResAirline = check airlineReservationEP->post("/reserve", <@untainted> outReqPayloadAirline);

        // Get the reservation status
        var airlineResPayload = check inResAirline.getJsonPayload();
        string airlineStatus = airlineResPayload.Status.toString();
        // If reservation status is negative, send a failure response to user
        if (internal:equalsIgnoreCase(airlineStatus, "Failed")) {
            outResponse.setJsonPayload({
                Message: "Failed to reserve airline! Provide a valid 'Preference' for 'Airline' and try again"
            });
            var result = caller->respond(outResponse);
            handleError(result);
            return;
        }

        // Reserve hotel room for the user by calling Hotel reservation service
        // construct the payload
        json outReqPayloadHotel = {
            Name: checkpanic inReqPayloadNameJson,
            ArrivalDate: checkpanic inReqPayloadArrivalDateJson,
            DepartureDate: checkpanic inReqPayloadDepartureDateJson,
            Preference: checkpanic hotelPreference
        };

        // Send a post request to hotelReservationService with appropriate payload and get response
        http:Response inResHotel = check hotelReservationEP->post("/reserve", <@untainted> outReqPayloadHotel);

        // Get the reservation status
        var hotelResPayload = check inResHotel.getJsonPayload();
        string hotelStatus = hotelResPayload.Status.toString();
        // If reservation status is negative, send a failure response to user
        if (internal:equalsIgnoreCase(hotelStatus, "Failed")) {
            outResponse.setJsonPayload({
                Message: "Failed to reserve hotel! Provide a valid 'Preference' for 'Accommodation' and try again"
            });
            var result = caller->respond(outResponse);
            handleError(result);
            return;
        }

        // Renting car for the user by calling Car rental service
        // construct the payload
        json outReqPayloadCar = {
            Name: checkpanic inReqPayloadNameJson,
            ArrivalDate: checkpanic inReqPayloadArrivalDateJson,
            DepartureDate: checkpanic inReqPayloadDepartureDateJson,
            Preference: checkpanic carPreference
        };

        // Send a post request to carRentalService with appropriate payload and get response
        http:Response inResCar = check carRentalEP->post("/rent", <@untainted> outReqPayloadCar);

        // Get the rental status
        var carResPayload = check inResCar.getJsonPayload();
        string carRentalStatus = carResPayload.Status.toString();
        // If rental status is negative, send a failure response to user
        if (internal:equalsIgnoreCase(carRentalStatus, "Failed")) {
            outResponse.setJsonPayload({
                "Message": "Failed to rent car! Provide a valid 'Preference' for 'Car' and try again"
            });
            var result = caller->respond(outResponse);
            handleError(result);
            return;
        }

        // If all three services response positive status, send a successful message to the user
        outResponse.setJsonPayload({
            Message: "Congratulations! Your journey is ready!!"
        });
        var result = caller->respond(outResponse);
        handleError(result);
        return ();
    }
}

function handleError(error? result) {
    if (result is error) {
        log:printError(result.reason(), result);
    }
}
