import { register, start as startControllers } from "./runtime/controllers.js"
import { start as startConfirm } from "./runtime/confirm.js"
import { start as startFrames } from "./runtime/frames.js"

import AskController from "./controllers/ask_controller.js"
import ChartController from "./controllers/chart_controller.js"
import ChatAskController from "./controllers/chat_ask_controller.js"
import ChatStreamController from "./controllers/chat_stream_controller.js"
import CheckAllController from "./controllers/check_all_controller.js"
import FilterController from "./controllers/filter_controller.js"
import FilterModalController from "./controllers/filter_modal_controller.js"
import FiltersController from "./controllers/filters_controller.js"
import JourneyController from "./controllers/journey_controller.js"
import KeywordFormController from "./controllers/keyword_form_controller.js"
import KeywordListController from "./controllers/keyword_list_controller.js"
import MenuController from "./controllers/menu_controller.js"
import MetricController from "./controllers/metric_controller.js"
import ModalController from "./controllers/modal_controller.js"
import PaletteController from "./controllers/palette_controller.js"
import PatternPreviewController from "./controllers/pattern_preview_controller.js"
import PickerController from "./controllers/picker_controller.js"
import PlacePickerController from "./controllers/place_picker_controller.js"
import RealtimeController from "./controllers/realtime_controller.js"
import SparkController from "./controllers/spark_controller.js"
import TabsController from "./controllers/tabs_controller.js"
import TagFieldController from "./controllers/tag_field_controller.js"
import ToastController from "./controllers/toast_controller.js"

register("dash--ask", AskController)
register("dash--chart", ChartController)
register("dash--chat-ask", ChatAskController)
register("dash--chat-stream", ChatStreamController)
register("dash--check-all", CheckAllController)
register("dash--filter", FilterController)
register("dash--filter-modal", FilterModalController)
register("dash--filters", FiltersController)
register("dash--journey", JourneyController)
register("dash--keyword-form", KeywordFormController)
register("dash--keyword-list", KeywordListController)
register("dash--menu", MenuController)
register("dash--metric", MetricController)
register("dash--modal", ModalController)
register("dash--palette", PaletteController)
register("dash--pattern-preview", PatternPreviewController)
register("dash--picker", PickerController)
register("dash--place-picker", PlacePickerController)
register("dash--realtime", RealtimeController)
register("dash--spark", SparkController)
register("dash--tabs", TabsController)
register("dash--tag-field", TagFieldController)
register("dash--toast", ToastController)

startControllers()
startConfirm()
startFrames()
