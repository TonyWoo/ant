#include <databinding/DataEvent.h>
#include <core/Element.h>
#include <core/Event.h>
#include <databinding/DataExpression.h>
#include <databinding/DataModel.h>

namespace Rml {

struct DataEventListener : public EventListener {
	DataEventListener(const std::string& type, DataExpression&& expr)
		: EventListener(type, false)
		, expression(std::move(expr))
	{ }
	void ProcessEvent(Event& event) override {
		Element* element = event.GetTargetElement();
		DataExpressionInterface expr_interface(element->GetDataModel(), element, &event);
		DataVariant unused_value_out;
		expression.Run(expr_interface, unused_value_out);
	}
	DataExpression expression;
};

DataEvent::DataEvent(Element* element)
	: element(element->GetObserverPtr())
	, listener(nullptr)
{}

DataEvent::~DataEvent() {
	if (element && listener) {
		element->RemoveEventListener(listener);
	}
}

bool DataEvent::Initialize(DataModel& model, Element* element, const std::string& expression_str, const std::string& modifier) {
	assert(element);
	DataExpression expression;
	DataExpressionInterface expr_interface(&model, element);
	if (!expression.Parse(expr_interface, expression_str, true)) {
		return false;
	}
	listener = new DataEventListener(modifier, std::move(expression));
	element->AddEventListener(listener);
	return true;
}

Element* DataEvent::GetElement() const {
	return element.get();
}

}
