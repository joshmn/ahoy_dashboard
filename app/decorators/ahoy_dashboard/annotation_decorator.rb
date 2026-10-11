module AhoyDashboard
  class AnnotationDecorator < AhoyDashboard::Decorator
    def kind_label
      AhoyDashboard::Annotation::KINDS.fetch(kind, AhoyDashboard::Annotation::KINDS.fetch(AhoyDashboard::Annotation::DEFAULT_KIND))
    end
  end
end
