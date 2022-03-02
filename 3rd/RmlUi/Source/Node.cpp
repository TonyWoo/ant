#include "../Include/RmlUi/Node.h"
#include "../Include/RmlUi/Debug.h"
#include "../Include/RmlUi/Element.h"
#include <yoga/YGNode.h>

namespace Rml {

Node::~Node()
{}

void Node::SetType(Type type_) {
	type = type_;
}

Node::Type Node::GetType() {
	return type;
}

bool Node::UpdateVisible() {
	return layout.UpdateVisible(metrics);
}

void Node::UpdateMetrics(Rect& child) {
	layout.UpdateMetrics(metrics, child);
}

Layout& Node::GetLayout() {
	return layout;
}

const Layout::Metrics& Node::GetMetrics() const {
	return metrics;
}

bool Node::IsVisible() const {
	return metrics.visible;
}

void Node::SetVisible(bool visible) {
// fixed nested data-if for same variant bug
// 	if (IsVisible() == visible) {
// 		return;
// 	}
	layout.SetVisible(visible);
}

void Node::SetParentNode(Element* parent_) {
	parent = parent_;
}

Element* Node::GetParentNode() const {
	return parent;
}

void Node::DirtyLayout() {
	layout.MarkDirty();
}

void Node::SetScrollTop(float top) {
	if (layout.GetOverflow() != Layout::Overflow::Scroll) {
		return;
	}
	metrics.scrollOffset.h = top;
	layout.UpdateScrollOffset(metrics);
}

void Node::SetScrollLeft(float left) {
	if (layout.GetOverflow() != Layout::Overflow::Scroll) {
		return;
	}
	metrics.scrollOffset.w = left;
	layout.UpdateScrollOffset(metrics);
}

Size Node::GetScrollOffset() const {
	return metrics.scrollOffset;
}

}
