const LOGIN = "https://order.dominos.com/power/login";
const EASYORDER = "https://order.dominos.com/power/customer/%s/order?_=%s";

const PRICE = "https://order.dominos.com/power/price-order";
const PLACE = "https://order.dominos.com/power/place-order";
const CARDS = "https://order.dominos.com/power/customer/%s/card?_=%s";

DEBUG <- true;      // Set to False to order pizza

username <- "";     // Your Dominos Username 
password <- "";     // Your Dominos Password

cardTypes <- {
    "VISA": "CreditCard"
};

function logTable(t, i = 0) {
    local indentString = "";
    for(local x = 0; x < i; x++) indentString += ".";
    
    foreach(k, v in t) {
        if (typeof(v) == "table" || typeof(v) == "array") {
            local par = "[]";
            if (typeof(v) == "table") par = "{}";
            
            server.log(indentString + k + ": " + par[0].tochar());
            logTable(v, i+4);
            server.log(indentString + par[1].tochar());
        } 
        else { 
            server.log(indentString + k + ": " + v);
        }
    }
}

function login(_username = username, _password = password) {
    local headers = {};
    local data = http.urlencode({ u=_username, p=_password });
    local response = http.post(LOGIN, headers, data).sendsync();
    if (response.statuscode == 200) {
        local data = http.jsondecode(response.body);
        username = _username;
        password = _password;

        return data;
    }
    else {
        server.log("ERROR - " + response.statuscode + ": " + response.body);
        username = null;
        password = null;
        return null;
    }
}

function getCards(user) {
    local headers = {
        Accept = "application/vnd.dominos.customer.card+json;version=1.0",
        Authorization = format("Basic %s", http.base64encode(format("%s:%s", username, password))),
        "Content-Type": "application/json",
        Origin = "https://order.dominos.com"
    };

    local url = format(CARDS, user.CustomerID, time().tostring());

    local response = http.get(url, headers).sendsync();
    local data = http.jsondecode(response.body);
    if (response.statuscode == 200) {
        return data;
    }
    return null;
}

function getEasyOrder(user) {
    local headers = {
        Accept = "application/json, text/javascript, */*; q=0.01",
        Authorization = format("Basic %s", http.base64encode(format("%s:%s", username, password))),
        "Content-Type": "application/json",
        Origin = "https://order.dominos.com"
    };

    local url = format(EASYORDER, user.CustomerID, time().tostring());
    local response = http.get(url, headers).sendsync();

    local data = http.jsondecode(response.body);
    if (response.statuscode == 200 && "easyOrder" in data) {
        local easyOrder = data.easyOrder.order;
        // build and return order object
        local order = {
            Order = {
                Address = easyOrder.Address,
                Coupons = [],
                Products = [],
                ServiceMethod = easyOrder.ServiceMethod,
                StoreID = easyOrder.StoreID
            }
        };
        foreach(product in easyOrder.Products) {
            order.Order.Products.push({
                Code = product.Code,
                ID = product.ID,
                Options = product.Options
                Qty = product.Qty,
            });
        }
        
        foreach(coupon in easyOrder.Coupons) {
            order.Order.Coupons.push({
                Code = coupon.Code,
                ID = coupon.ID,
                Qty = coupon.Qty
            });
        }
        
        return order;
    }
    return null;    
}

function priceOrder(order) {
    local headers = {
        Accept = "application/json, text/javascript, */*; q=0.01",
        Authorization = format("Basic %s", http.base64encode(format("%s:%s", username, password))),
        Origin = "https://order.dominos.com",
        "Content-Type": "application/json; charset=UTF-8"
    };
    
    local response = http.post(PRICE, headers, http.jsonencode(order)).sendsync();
    if (response.statuscode == 200) {
        local pricedOrder = http.jsondecode(response.body);
        return pricedOrder
    } else {
        server.log("ERROR CREATING ORDER - " + response.statuscode + ": " + response.body);
        return null;
    }
    
}

function sendOrder(order, user, card) {
    local headers = {
        Accept = "application/vnd.dominos.customer.card+json;version=1.0",
        Authorization = format("Basic %s", http.base64encode(format("%s:%s", username, password))),
        Origin = "https://order.dominos.com",
        "Content-Type": "application/json; charset=UTF-8"
    }

    if (!(card.cardType in cardTypes)) return null;
    
    local finalizedOrder = {
        Order = {
            Address = order.Address,
            Coupons = [],
            CustomerID = user.CustomerID,
            Email = user.Email,
            Extension = user.Extension,
            FirstName = user.FirstName,
            LastName = user.LastName,
            LanguageCode = "en",
            NoCombine = true,
            OrderChannel = "OLO",
            OrderID = order.OrderID,
            OrderMethod = "Web",
            OrderTaker = null,
            Partners = {},
            Payments = [{
                Amount = order.Amounts.Customer,
                CardID = card.id,
                Type = cardTypes[card.cardType]
            }],
            Phone = user.Phone
            Products = [],
            ServiceMethod = order.ServiceMethod,
            SourceOrganizationURI = "order.dominos.com",
            StoreID = order.StoreID,
            Tags = {},
            Version = "1.0",
        }
    };
    
    foreach(product in order.Products) {
        finalizedOrder.Order.Products.push({
            Code = product.Code,
            ID = product.ID,
            Options = "Options" in product ? product["Options"] : {},
            Qty = product.Qty,
        });
    }
    
    foreach(coupon in order.Coupons) {
        finalizedOrder.Order.Coupons.push({
            Code = coupon.Code,
            ID = coupon.ID,
            Qty = coupon.Qty
        });
    }

    if (DEBUG) {
        // If we're in DEBUG, log request to return.. don't send the order
        server.log("DEBUG set to true - not ordering a pizza");
        logTable(finalizedOrder);
        return;
    }

    local response = http.post(PLACE, headers, http.jsonencode(finalizedOrder)).sendsync();
    server.log(response.statuscode);
    server.log(response.body);
    logTable(http.jsondecode(response.body));
}

device.on("buttonPress", function(nullData) {
    server.log("Got it");
    
    local user = login();
    if (!user) {
    	server.log("ERROR: No User");
    	return;
    }
    server.log("Logged In.")
    
    local easyOrder = getEasyOrder(user);
    if (!easyOrder) {
    	server.log("ERROR: No Easy Order");
    	return;
    }
    server.log("Got Easy Order");
    
    local order = priceOrder(easyOrder);
    if (!order) {
		server.log("ERROR: Could not create order");
    	return;
	}
    server.log("Created Order");
    
    local estimatedWaitTime = format("%s minutes", order.Order.EstimatedWaitMinutes);
    local totalCost = format("$%s", order.Order.Amounts.Payment.tostring());

    server.log(format("Looks like someone just made a %s pizza order that should be delivered to %s in %s.\n", totalCost, order.Order.Address.Street, estimatedWaitTime));

    local cards = getCards(user);
    if (!cards) {
    	server.log("ERROR: No Credit Card");
    	return;
    }
    sendOrder(order.Order, user, cards[0]);
});